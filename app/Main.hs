-- | The @hclean@ executable: argument handling, prompting and exit codes.
module Main (main) where

import Control.Monad (forM_, unless, when)
import Data.Char (toLower)
import Data.List (intercalate, sortOn)
import System.Directory (doesDirectoryExist, makeAbsolute)
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.FilePath (normalise)
import System.IO (hFlush, hPutStrLn, stderr, stdout)

import CLI (Command (..), Invocation (..), helpText, parseArgs, versionText)
import HClean.Config (configFileName, resolveConfig, writeDefaultConfig)
import HClean.Delete (removePath)
import HClean.Glob (validGlob)
import HClean.Preset (defaultPatterns, expandPresets, isPresetName, presetNames, resolvePatterns)
import HClean.Report (Summary (..), renderJson, renderText, summarize)
import HClean.Scan (ScanHooks (..), scanWith)
import HClean.Types (Options (..), OutputFormat (..), Target (..))
import Progress (Progress (..), withProgress)

main :: IO ()
main = do
  args <- getArgs
  case parseArgs args of
    Left err -> die err
    Right inv -> case invCommand inv of
      ShowHelp -> putStr helpText
      ShowVersion -> putStrLn versionText
      command -> do
        opts <- resolveConfig (invConfig inv) (invOptions inv)
        mapM_ die (validate opts)
        case command of
          WriteConfig -> do
            written <- writeDefaultConfig configFileName
            unless written $
              die ("Cannot overwrite existing '" ++ configFileName ++ "' file")
          ListPatterns -> mapM_ putStrLn (listedPatterns opts)
          _ -> runClean inv opts

-- | Scan the tree, report what matched and offer to delete it.
runClean :: Invocation -> Options -> IO ()
runClean inv opts = do
  usable <- doesDirectoryExist (optRoot opts)
  unless usable $ die ("invalid path: " ++ optRoot opts)
  root <- normalise <$> makeAbsolute (optRoot opts)
  let patterns = resolvePatterns opts
  summary <- withProgress (invProgress inv) scanning scanned $ \progress -> do
    note progress ("root: " ++ root)
    note progress ("patterns: " ++ intercalate ", " patterns)
    targets <- scanWith (hooks progress) opts root patterns
    progressMessage progress (const "measuring sizes")
    summarize (sortOn targetPath targets)
  case optFormat opts of
    JsonFormat -> putStrLn (renderJson (optDryRun opts) summary)
    TextFormat -> unless (optQuiet opts) $ putStr (renderText (optStats opts) summary)
  unless (optDryRun opts || null (summaryTargets summary)) $ do
    confirmed <- confirm opts
    when confirmed $ delete inv (summaryTargets summary)
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

-- | Remove the targets, showing progress and narrating them when verbose.
delete :: Invocation -> [Target] -> IO ()
delete inv targets =
  withProgress (invProgress inv) removing (const Nothing) $ \progress -> do
    forM_ targets $ \t -> do
      progressTick progress (targetPath t)
      when (invVerbose inv) (progressNote progress ("removing " ++ targetPath t))
      removePath (targetPath t)
    when (invVerbose inv) $
      progressNote progress ("removed " ++ show (length targets) ++ " item(s)")
  where
    removing n = "removing, " ++ show n ++ " of " ++ show (length targets)

-- | Ask before deleting, unless the user opted out.
confirm :: Options -> IO Bool
confirm opts
  | optAssumeYes opts = pure True
  | otherwise = do
      putStr "Do you want to delete the above? [y/N] "
      hFlush stdout
      answer <- getLine
      pure (map toLower answer `elem` ["y", "yes"])

-- | Patterns printed by @--list@: the presets asked for, or the defaults.
listedPatterns :: Options -> [String]
listedPatterns opts
  | null (optPresets opts) = defaultPatterns
  | otherwise              = expandPresets (optPresets opts)

-- | Checks that must pass before anything touches the file system.
validate :: Options -> Maybe String
validate opts
  | (bad : _) <- filter (not . isPresetName) (optPresets opts) =
      Just ("unknown preset '" ++ bad ++ "' (use " ++ orList presetNames ++ ")")
  | (bad : _) <- filter (not . validGlob) (resolvePatterns opts) =
      Just ("invalid glob pattern: " ++ bad)
  | otherwise = Nothing

orList :: [String] -> String
orList []  = ""
orList [x] = x
orList xs  = foldr1 (\a b -> a ++ ", " ++ b) (init xs) ++ ", or " ++ last xs

die :: String -> IO a
die msg = hPutStrLn stderr msg >> exitFailure
