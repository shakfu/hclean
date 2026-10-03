-- | Command line surface: argument parsing, help text and version.
--
-- This module is deliberately the only place that knows about @argv@; it
-- produces an 'Invocation' that the library can act on.
module CLI
  ( Invocation(..)
  , Command(..)
  , parseArgs
  , helpText
  , versionText
  ) where

import Data.List (isPrefixOf)

import HClean.Config (ConfigSource (..), configFileName)
import Progress (ProgressMode (..))
import HClean.Preset (presetNames)
import HClean.Types (Options (..), OutputFormat (..), defaultOptions)
import HClean.Util (parseDuration)

-- | What the user asked hclean to do.
data Command
  = Clean         -- ^ Scan and (unless dry running) delete.
  | ListPatterns  -- ^ Print the patterns that would be used.
  | WriteConfig   -- ^ Write a starter config file.
  | ShowHelp
  | ShowVersion
  deriving (Eq, Show)

-- | A fully parsed command line.
data Invocation = Invocation
  { invCommand  :: Command
  , invOptions  :: Options
  , invConfig   :: ConfigSource
  , invVerbose  :: Bool  -- ^ Log what is scanned and removed, on stderr.
  , invProgress :: ProgressMode  -- ^ Whether to show the activity indicator.
  }
  deriving (Eq, Show)

defaultInvocation :: Invocation
defaultInvocation = Invocation
  { invCommand  = Clean
  , invOptions  = defaultOptions
  , invConfig   = NoConfig
  , invVerbose  = False
  , invProgress = ProgressAuto
  }

-- | Parse @argv@, or report the first problem found.
parseArgs :: [String] -> Either String Invocation
parseArgs = go defaultInvocation
  where
    go inv [] = Right inv
    go inv (arg : rest) = case arg of
      "-h"                        -> command ShowHelp
      "--help"                    -> command ShowHelp
      "--version"                 -> command ShowVersion
      "-l"                        -> command ListPatterns
      "--list"                    -> command ListPatterns
      "-w"                        -> command WriteConfig
      "--write-configfile"        -> command WriteConfig
      "-p"                        -> withValue (\v o -> o { optRoot = Just v })
      "--path"                    -> withValue (\v o -> o { optRoot = Just v })
      "-g"                        -> withValue (\v o -> o { optIncludes = optIncludes o ++ [v] })
      "--glob"                    -> withValue (\v o -> o { optIncludes = optIncludes o ++ [v] })
      "-e"                        -> withValue (\v o -> o { optExcludes = optExcludes o ++ [v] })
      "--exclude"                 -> withValue (\v o -> o { optExcludes = optExcludes o ++ [v] })
      "--preset"                  -> withValue (\v o -> o { optPresets = optPresets o ++ [v] })
      "-d"                        -> flag (\o -> o { optDryRun = True })
      "--dry-run"                 -> flag (\o -> o { optDryRun = True })
      "-y"                        -> flag (\o -> o { optAssumeYes = True })
      "--skip-confirmation"       -> flag (\o -> o { optAssumeYes = True })
      "-s"                        -> flag (\o -> o { optStats = True })
      "--stats"                   -> flag (\o -> o { optStats = True })
      "-i"                        -> flag (\o -> o { optSymlinks = True })
      "--include-symlinks"        -> flag (\o -> o { optSymlinks = True })
      "-r"                        -> flag (\o -> o { optBrokenSymlinks = True })
      "--remove-broken-symlinks"  -> flag (\o -> o { optBrokenSymlinks = True })
      "-B"                        -> flag (\o -> o { optArtifacts = True })
      "--build-artifacts"         -> flag (\o -> o { optArtifacts = True })
      "--no-protect"              -> flag (\o -> o { optNoProtect = True })
      "-q"                        -> flag (\o -> o { optQuiet = True })
      "--quiet"                   -> flag (\o -> o { optQuiet = True })
      "-v"                        -> go inv { invVerbose = True } rest
      "--verbose"                 -> go inv { invVerbose = True } rest
      "-P"                        -> go inv { invProgress = ProgressAlways } rest
      "--progress"                -> go inv { invProgress = ProgressAlways } rest
      "--no-progress"             -> go inv { invProgress = ProgressNever } rest
      "-o"                        -> olderThan
      "--older-than"              -> olderThan
      "--format"                  -> format
      "-c"                        -> configFile
      "--configfile"              -> configFile
      _ | "--format=" `isPrefixOf` arg -> setFormat (drop (length "--format=") arg) rest
        | otherwise -> Left ("unknown or incomplete option: " ++ arg)
      where
        command c = go inv { invCommand = c } rest

        flag f = go inv { invOptions = f (invOptions inv) } rest

        withValue f = case rest of
          (v : more) -> go inv { invOptions = f v (invOptions inv) } more
          []         -> Left ("unknown or incomplete option: " ++ arg)

        olderThan = case rest of
          (v : more) -> case parseDuration v of
            Left err -> Left err
            Right seconds ->
              go inv { invOptions = (invOptions inv) { optOlderThan = Just seconds } } more
          [] -> Left ("unknown or incomplete option: " ++ arg)

        format = case rest of
          (v : more) -> setFormat v more
          []         -> Left ("unknown or incomplete option: " ++ arg)

        setFormat v more = case v of
          "json" -> go inv { invOptions = (invOptions inv) { optFormat = JsonFormat } } more
          "text" -> go inv { invOptions = (invOptions inv) { optFormat = TextFormat } } more
          _      -> Left ("unknown output format: " ++ v)

        -- @-c@ takes an optional path; a following flag means "discover".
        configFile = case rest of
          (v : more) | not ("-" `isPrefixOf` v) -> go inv { invConfig = ConfigFile v } more
          _                                     -> go inv { invConfig = DiscoverConfig } rest

versionText :: String
versionText = "hclean 0.1.0"

helpText :: String
helpText = unlines
  [ "Safely remove files and directories matching glob patterns."
  , ""
  , "Usage: hclean [OPTIONS]"
  , "  -p, --path PATH               Working directory (default .)"
  , "  -g, --glob GLOB               Include pattern (repeatable)"
  , "  -e, --exclude GLOB            Exclude pattern (repeatable)"
  , "      --preset NAME             " ++ presetList
  , "  -d, --dry-run                 Preview matches"
  , "  -y, --skip-confirmation       Do not prompt"
  , "  -s, --stats                   Show statistics"
  , "  -o, --older-than DURATION     s, m, h, d, or w"
  , "  -B, --build-artifacts         Match project build output"
  , "  -i, --include-symlinks        Remove matching symlinks"
  , "  -r, --remove-broken-symlinks  Remove broken symlinks"
  , "  -c, --configfile [PATH]       Read configuration (discovered if omitted)"
  , "      --format text|json        Output format"
  , "      --no-protect              Disable protected directories"
  , "  -q, --quiet                   Suppress the match listing"
  , "  -v, --verbose                 Log scanning and removal on stderr"
  , "  -P, --progress                Always report progress, terminal or not"
  , "      --no-progress             Never show the activity indicator"
  , "  -l, --list                    List patterns"
  , "  -w, --write-configfile        Write " ++ configFileName ++ " in --path"
  , "  -h, --help                    Show this help"
  , "      --version                 Show version"
  ]
  where
    presetList = case presetNames of
      []     -> ""
      (p:ps) -> foldl (\acc n -> acc ++ ", " ++ n) p ps
