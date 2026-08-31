-- | Reading and writing the @.rclean.toml@ configuration file.
--
-- Only the small subset of TOML that the file format actually uses is
-- understood: top level @key = value@ lines with string, boolean and string
-- array values.
--
-- Precedence: a list given on the command line (@--glob@, @--exclude@,
-- @--preset@) replaces the corresponding config list entirely, a boolean flag
-- given on the command line cannot be turned off by the file, and @path@ from
-- the file wins over the default but is overridden by an explicit @--path@
-- only if that option was given (there is no way to distinguish an explicit
-- @--path .@ from the default, which is why the file wins there).
module HClean.Config
  ( ConfigSource(..)
  , resolveConfig
  , applyConfig
  , discoverConfig
  , writeDefaultConfig
  , configFileName
  , defaultConfigContents
  ) where

import Data.List (isPrefixOf)
import Data.Maybe (fromMaybe, listToMaybe)
import System.Directory (doesFileExist)
import System.Environment (lookupEnv)
import System.FilePath ((</>), normalise, takeDirectory)

import HClean.Types (Options (..))
import HClean.Util (trim)

-- | Where configuration should come from.
data ConfigSource
  = NoConfig            -- ^ Ignore configuration files entirely.
  | DiscoverConfig      -- ^ Search upwards, then fall back to the global file.
  | ConfigFile FilePath -- ^ Read this file.
  deriving (Eq, Show)

-- | Name looked for during discovery, and written by @--write-configfile@.
configFileName :: FilePath
configFileName = ".rclean.toml"

-- | Apply the selected configuration source to a set of options.
resolveConfig :: ConfigSource -> Options -> IO Options
resolveConfig NoConfig o = pure o
resolveConfig (ConfigFile p) o = applyConfig p o
resolveConfig DiscoverConfig o =
  maybe (pure o) (`applyConfig` o) =<< discoverConfig "."

-- | Merge a config file into @o@; values already set on the command line win.
applyConfig :: FilePath -> Options -> IO Options
applyConfig path o = do
  text <- readConfigFile path
  let value key = lookupValue key text
      array key = maybe [] parseArray (value key)
      flag key = maybe False ((== "true") . trim) (value key)
      keep current fromFile = if null current then fromFile else current
  pure o
    { optRoot           = fromMaybe (optRoot o) (value "path")
    , optIncludes       = keep (optIncludes o) (array "patterns")
    , optExcludes       = keep (optExcludes o) (array "exclude_patterns")
    , optPresets        = keep (optPresets o) (array "presets")
    , optDryRun         = optDryRun o || flag "dry_run"
    , optAssumeYes      = optAssumeYes o || flag "skip_confirmation"
    , optStats          = optStats o || flag "stats_mode"
    , optSymlinks       = optSymlinks o || flag "include_symlinks"
    , optBrokenSymlinks = optBrokenSymlinks o || flag "remove_broken_symlinks"
    , optArtifacts      = optArtifacts o || flag "build_artifacts"
    }

-- | Look for 'configFileName' in @start@ and its ancestors, then in
-- @~\/.config\/rclean\/config.toml@.
discoverConfig :: FilePath -> IO (Maybe FilePath)
discoverConfig start = climb (normalise start)
  where
    climb dir = do
      let candidate = dir </> configFileName
      here <- doesFileExist candidate
      if here
        then pure (Just candidate)
        else let parent = takeDirectory dir
             in if parent == dir then global else climb parent

    global = do
      home <- lookupEnv "HOME"
      case home of
        Nothing -> pure Nothing
        Just h -> do
          let p = h </> ".config" </> "rclean" </> "config.toml"
          exists <- doesFileExist p
          pure (if exists then Just p else Nothing)

-- | Contents written by @--write-configfile@.
defaultConfigContents :: String
defaultConfigContents = unlines
  [ "path = \".\""
  , "patterns = [\"**/__pycache__\", \"**/*.pyc\"]"
  ]

-- | Write a starter config file. Returns 'False' without touching anything if
-- the file already exists.
writeDefaultConfig :: FilePath -> IO Bool
writeDefaultConfig path = do
  exists <- doesFileExist path
  if exists
    then pure False
    else True <$ writeFile path defaultConfigContents

-- | Read a config file completely, so the handle does not outlive the call.
readConfigFile :: FilePath -> IO String
readConfigFile path = do
  text <- readFile path
  length text `seq` pure text

lookupValue :: String -> String -> Maybe String
lookupValue key text = listToMaybe
  [ unquote (trim (drop 1 (dropWhile (/= '=') l)))
  | l <- lines text
  , key `isPrefixOf` trim l
  , '=' `elem` l
  ]

parseArray :: String -> [String]
parseArray s =
  [ unquote (trim item)
  | item <- splitOn ',' (takeWhile (/= ']') (drop 1 (dropWhile (/= '[') s)))
  , not (null (trim item))
  ]

-- | Strip surrounding double quotes from a TOML string value.
unquote :: String -> String
unquote ('"' : xs) | not (null xs) && last xs == '"' = init xs
unquote x = x

splitOn :: Char -> String -> [String]
splitOn _ [] = []
splitOn c xs = case break (== c) xs of
  (a, [])       -> [a]
  (a, _ : rest) -> a : splitOn c rest
