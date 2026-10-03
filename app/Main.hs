-- | The @hclean@ executable: argument handling, prompting and exit codes.
module Main (main) where

import Control.Exception (IOException, handle, try)
import Control.Monad (forM_, unless, when)
import Data.Char (toLower)
import Data.List (intercalate, sortOn)
import Data.Maybe (fromMaybe)
import GHC.IO.Encoding (getFileSystemEncoding)
import System.Directory (doesDirectoryExist, makeAbsolute)
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.FilePath ((</>), normalise)
import System.IO (hFlush, hPutStr, hPutStrLn, hSetEncoding, stderr, stdout)

import CLI (Command (..), Invocation (..), helpText, parseArgs, versionText)
import HClean.Config (configFileName, resolveConfig, writeDefaultConfig)
import HClean.Delete (Failure (..), removeTargets)
import HClean.Glob (validGlob)
import HClean.Preset (isPresetName, presetNames, resolvePatterns)
import HClean.Report (Summary (..), renderJson, renderRemoved, renderText, summarize)
import HClean.Scan (ScanHooks (..), scanWith)
import HClean.Types (Options (..), OutputFormat (..), Target (..), scanRoot)
import HClean.Util (trim)
import Progress (Progress (..), withProgress)

main :: IO ()
main = handle (\e -> die (show (e :: IOException))) $ do
  -- File names are decoded with the file system encoding, which keeps bytes
  -- invalid in the locale as surrogates; encoding output the same way writes
  -- those bytes back instead of throwing.
  encoding <- getFileSystemEncoding
  mapM_ (`hSetEncoding` encoding) [stdout, stderr]
  args <- getArgs
  case parseArgs args of
    Left err -> die err
    Right inv -> case invCommand inv of
      ShowHelp -> putStr helpText
      ShowVersion -> putStrLn versionText
      command -> do
        opts <- either die pure =<< resolveConfig (invConfig inv) (invOptions inv)
        mapM_ die (validate opts)
        case command of
          WriteConfig -> do
            requireDirectory (scanRoot opts)
            let path = maybe configFileName (</> configFileName) (optRoot opts)
            written <- writeDefaultConfig path
            unless written $
              die ("Cannot overwrite existing '" ++ path ++ "' file")
          ListPatterns -> mapM_ putStrLn (resolvePatterns opts)
          _ -> runClean inv opts

-- | Scan the tree, report what matched and offer to delete it.
runClean :: Invocation -> Options -> IO ()
runClean inv opts = do
  let dir = scanRoot opts
  requireDirectory dir
  root <- normalise <$> makeAbsolute dir
  let patterns = resolvePatterns opts
      -- Only --stats and JSON show sizes, and measuring walks every match.
      measure = optStats opts || optFormat opts == JsonFormat
  summary <- withProgress (invProgress inv) scanning scanned $ \progress -> do
    note progress ("root: " ++ root)
    note progress ("patterns: " ++ intercalate ", " patterns)
    targets <- scanWith (hooks progress) opts root patterns
    progressMessage progress (const "measuring sizes")
    summarize measure (sortOn targetPath targets)
  let matched = summaryTargets summary
  failures <- case optFormat opts of
    TextFormat -> do
      unless (optQuiet opts) $ putStr (renderText (optStats opts) summary)
      removal <- removeConfirmed inv opts matched
      case removal of
        Nothing -> pure []
        Just (failures, freed) -> do
          unless (optQuiet opts) $
            putStr (renderRemoved (length matched - length failures) freed)
          forM_ failures $ \f -> hPutStrLn stderr ("hclean: " ++ failureError f)
          pure failures
    JsonFormat -> do
      (failures, freed) <- fromMaybe ([], 0) <$> removeConfirmed inv opts matched
      putStrLn (renderJson (optDryRun opts) failures freed summary)
      pure failures
  unless (null failures) exitFailure
  where
    scanning n = "scanning, " ++ show n ++ " entries"
    scanned n = Just ("scanned " ++ show n ++ " entries")

    hooks progress = ScanHooks
      { onVisit = progressTick progress
      , onMatch = \t ->
          note progress ("match: " ++ targetPath t ++ " (" ++ targetPattern t ++ ")")
      }

    -- Verbose logging goes through the indicator so the two do not collide.
    note progress msg = when (invVerbose inv) (progressNote progress msg)

-- | Remove the targets if this is not a dry run and the user agrees.
-- 'Nothing' when nothing was attempted; otherwise the failures and bytes freed.
removeConfirmed :: Invocation -> Options -> [Target] -> IO (Maybe ([Failure], Integer))
removeConfirmed inv opts targets
  | optDryRun opts || null targets = pure Nothing
  | otherwise = do
      confirmed <- confirm opts (length targets)
      if confirmed then Just <$> delete inv targets else pure Nothing

-- | Remove the targets, showing progress and narrating them when verbose.
delete :: Invocation -> [Target] -> IO ([Failure], Integer)
delete inv targets =
  withProgress (invProgress inv) removing (const Nothing) $ \progress -> do
    result@(failures, _) <- removeTargets (before progress) targets
    when (invVerbose inv) $
      progressNote progress
        ("removed " ++ show (length targets - length failures) ++ " item(s)")
    pure result
  where
    removing n = "removing, " ++ show n ++ " of " ++ show (length targets)

    before progress t = do
      progressTick progress (targetPath t)
      when (invVerbose inv) (progressNote progress ("removing " ++ targetPath t))

-- | Ask before deleting, unless the user opted out. The prompt goes to stderr
-- so stdout carries only the report; end of input means no.
confirm :: Options -> Int -> IO Bool
confirm opts count
  | optAssumeYes opts = pure True
  | otherwise = do
      hFlush stdout
      hPutStr stderr ("Delete " ++ show count ++ " item(s)? [y/N] ")
      hFlush stderr
      answer <- try getLine :: IO (Either IOException String)
      pure (either (const False) ((`elem` ["y", "yes"]) . map toLower . trim) answer)

-- | Exit unless @dir@ is a directory.
requireDirectory :: FilePath -> IO ()
requireDirectory dir = do
  usable <- doesDirectoryExist dir
  unless usable $ die ("invalid path: " ++ dir)

-- | Checks that must pass before anything touches the file system.
validate :: Options -> Maybe String
validate opts
  | (bad : _) <- filter (not . isPresetName) (optPresets opts) =
      Just ("unknown preset '" ++ bad ++ "' (use " ++ orList presetNames ++ ")")
  | (bad : _) <- filter (not . validGlob) (resolvePatterns opts ++ optExcludes opts) =
      Just ("invalid glob pattern: " ++ bad)
  | otherwise = Nothing

orList :: [String] -> String
orList []  = ""
orList [x] = x
orList xs  = foldr1 (\a b -> a ++ ", " ++ b) (init xs) ++ ", or " ++ last xs

die :: String -> IO a
die msg = hPutStrLn stderr ("hclean: " ++ msg) >> exitFailure
