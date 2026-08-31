module CLISpec (tests) where

import CLI
import HClean.Config (ConfigSource (..))
import HClean.Types (Options (..), OutputFormat (..), defaultOptions)
import Progress (ProgressMode (..))
import Harness

parseOptions :: [String] -> Either String Options
parseOptions = fmap invOptions . parseArgs

tests :: TestGroup
tests = group "CLI"
  [ it "defaults to cleaning the current directory" $ do
      assertEqual "command" (Right Clean) (fmap invCommand (parseArgs []))
      assertEqual "options" (Right defaultOptions) (parseOptions [])
      assertEqual "config" (Right NoConfig) (fmap invConfig (parseArgs []))
  , it "accepts long and short spellings of each flag" $ do
      let flags =
            [ (["-d"], ["--dry-run"])
            , (["-y"], ["--skip-confirmation"])
            , (["-s"], ["--stats"])
            , (["-i"], ["--include-symlinks"])
            , (["-r"], ["--remove-broken-symlinks"])
            , (["-B"], ["--build-artifacts"])
            , (["-q"], ["--quiet"])
            ]
      mapM_ (\(short, long) -> assertEqual (unwords short) (parseOptions short) (parseOptions long)) flags
  , it "sets the flags it is given" $ do
      assertEqual "dry run" (Right True) (fmap optDryRun (parseOptions ["-d"]))
      assertEqual "assume yes" (Right True) (fmap optAssumeYes (parseOptions ["-y"]))
      assertEqual "artifacts" (Right True) (fmap optArtifacts (parseOptions ["-B"]))
      assertEqual "no protect" (Right True) (fmap optNoProtect (parseOptions ["--no-protect"]))
  , it "collects repeated globs, excludes and presets in order" $ do
      assertEqual "globs"
        (Right ["a", "b"])
        (fmap optIncludes (parseOptions ["-g", "a", "--glob", "b"]))
      assertEqual "excludes"
        (Right ["x", "y"])
        (fmap optExcludes (parseOptions ["-e", "x", "--exclude", "y"]))
      assertEqual "presets"
        (Right ["node", "rust"])
        (fmap optPresets (parseOptions ["--preset", "node", "--preset", "rust"]))
  , it "parses the age limit" $ do
      assertEqual "hours" (Right (Just 7200)) (fmap optOlderThan (parseOptions ["-o", "2h"]))
      assertEqual "bad unit"
        (Left "duration unit must be s, m, h, d, or w")
        (fmap optOlderThan (parseOptions ["--older-than", "2y"]))
  , it "parses the output format in both spellings" $ do
      assertEqual "space" (Right JsonFormat) (fmap optFormat (parseOptions ["--format", "json"]))
      assertEqual "equals" (Right JsonFormat) (fmap optFormat (parseOptions ["--format=json"]))
      assertEqual "text" (Right TextFormat) (fmap optFormat (parseOptions ["--format", "text"]))
      assertEqual "unknown" (Left "unknown output format: yaml") (parseOptions ["--format=yaml"])
  , it "treats the config path as optional" $ do
      assertEqual "with path"
        (Right (ConfigFile "cfg.toml"))
        (fmap invConfig (parseArgs ["-c", "cfg.toml"]))
      assertEqual "bare" (Right DiscoverConfig) (fmap invConfig (parseArgs ["-c"]))
      assertEqual "followed by a flag"
        (Right DiscoverConfig)
        (fmap invConfig (parseArgs ["-c", "-d"]))
      assertEqual "still parses the flag" (Right True) (fmap optDryRun (parseOptions ["-c", "-d"]))
  , it "enables the diagnostics flags" $ do
      assertEqual "verbose" (Right True) (fmap invVerbose (parseArgs ["-v"]))
      assertEqual "long verbose" (Right True) (fmap invVerbose (parseArgs ["--verbose"]))
      assertEqual "progress" (Right ProgressAlways) (fmap invProgress (parseArgs ["-P"]))
      assertEqual "long progress" (Right ProgressAlways) (fmap invProgress (parseArgs ["--progress"]))
      assertEqual "no progress" (Right ProgressNever) (fmap invProgress (parseArgs ["--no-progress"]))
      assertEqual "automatic by default" (Right ProgressAuto) (fmap invProgress (parseArgs []))
      assertEqual "off by default" (Right False) (fmap invVerbose (parseArgs []))
  , it "recognises the non-cleaning commands" $ do
      assertEqual "help" (Right ShowHelp) (fmap invCommand (parseArgs ["--help"]))
      assertEqual "short help" (Right ShowHelp) (fmap invCommand (parseArgs ["-h"]))
      assertEqual "version" (Right ShowVersion) (fmap invCommand (parseArgs ["--version"]))
      assertEqual "list" (Right ListPatterns) (fmap invCommand (parseArgs ["-l"]))
      assertEqual "write config" (Right WriteConfig) (fmap invCommand (parseArgs ["-w"]))
  , it "reports unknown and incomplete options" $ do
      assertEqual "unknown"
        (Left "unknown or incomplete option: --bogus")
        (parseOptions ["--bogus"])
      assertEqual "missing value"
        (Left "unknown or incomplete option: -g")
        (parseOptions ["-g"])
      assertEqual "missing path"
        (Left "unknown or incomplete option: --path")
        (parseOptions ["--path"])
  , it "documents every option it accepts" $ do
      let documented = unwords (lines helpText)
      mapM_ (\flag -> assertBool (flag ++ " is undocumented") (flag `isIn` documented))
        [ "-p", "-g", "-e", "--preset", "-d", "-y", "-s", "-o", "-B", "-i", "-r"
        , "-c", "--format", "--no-protect", "-q", "-v", "-P", "--no-progress"
        , "-l", "-w", "-h", "--version"
        ]
  ]
  where
    isIn needle haystack = any (prefixed needle) (words haystack)
    prefixed needle w = needle == takeWhile (/= ',') w
