module ConfigSpec (tests) where

import System.Directory (withCurrentDirectory)
import System.FilePath ((</>))

import HClean.Config
import HClean.Types (Options (..), defaultOptions)
import Harness

configText :: String
configText = unlines
  [ "path = \"/srv/project\""
  , "patterns = [\"**/*.log\", \"**/*.tmp\"]"
  , "exclude_patterns = [\"**/keep\"]"
  , "presets = [\"rust\", \"go\"]"
  , "dry_run = true"
  , "skip_confirmation = true"
  , "stats_mode = true"
  , "include_symlinks = true"
  , "remove_broken_symlinks = true"
  , "build_artifacts = true"
  ]

tests :: TestGroup
tests = group "HClean.Config"
  [ it "reads every supported key" $
      withTree [(".rclean.toml", configText)] $ \root -> do
        o <- applyConfig (root </> ".rclean.toml") defaultOptions
        assertEqual "path" "/srv/project" (optRoot o)
        assertEqual "patterns" ["**/*.log", "**/*.tmp"] (optIncludes o)
        assertEqual "excludes" ["**/keep"] (optExcludes o)
        assertEqual "presets" ["rust", "go"] (optPresets o)
        assertEqual "dry run" True (optDryRun o)
        assertEqual "skip confirmation" True (optAssumeYes o)
        assertEqual "stats" True (optStats o)
        assertEqual "symlinks" True (optSymlinks o)
        assertEqual "broken symlinks" True (optBrokenSymlinks o)
        assertEqual "artifacts" True (optArtifacts o)
  , it "strips quotes from string values" $
      withTree [(".rclean.toml", "path = \".\"\n")] $ \root -> do
        o <- applyConfig (root </> ".rclean.toml") defaultOptions
        assertEqual "unquoted" "." (optRoot o)
  , it "lets command line lists win over the file" $
      withTree [(".rclean.toml", configText)] $ \root -> do
        o <- applyConfig (root </> ".rclean.toml")
               defaultOptions { optIncludes = ["**/*.bak"], optPresets = ["node"] }
        assertEqual "patterns" ["**/*.bak"] (optIncludes o)
        assertEqual "presets" ["node"] (optPresets o)
  , it "treats absent flags as off and never turns one off" $
      withTree [(".rclean.toml", "dry_run = false\n")] $ \root -> do
        o <- applyConfig (root </> ".rclean.toml") defaultOptions { optDryRun = True }
        assertEqual "still on" True (optDryRun o)
        o2 <- applyConfig (root </> ".rclean.toml") defaultOptions
        assertEqual "off" False (optDryRun o2)
  , it "finds the nearest config file walking upwards" $
      withTree [(".rclean.toml", "path = \".\"\n"), ("a/b/c/", "")] $ \root -> do
        found <- discoverConfig (root </> "a" </> "b" </> "c")
        assertEqual "ancestor" (Just (root </> ".rclean.toml")) found
  , it "prefers the closest config file" $
      withTree [(".rclean.toml", ""), ("a/.rclean.toml", ""), ("a/b/", "")] $ \root -> do
        found <- discoverConfig (root </> "a" </> "b")
        assertEqual "closest" (Just (root </> "a" </> ".rclean.toml")) found
  , it "writes a starter config and refuses to overwrite" $
      withTree [] $ \root -> withCurrentDirectory root $ do
        written <- writeDefaultConfig configFileName
        assertEqual "written" True written
        contents <- readFile configFileName
        assertEqual "contents" defaultConfigContents contents
        again <- writeDefaultConfig configFileName
        assertEqual "refused" False again
  , it "resolves the requested source" $
      withTree [(".rclean.toml", "dry_run = true\n")] $ \root -> do
        untouched <- resolveConfig NoConfig defaultOptions
        assertEqual "no config" defaultOptions untouched
        loaded <- resolveConfig (ConfigFile (root </> ".rclean.toml")) defaultOptions
        assertEqual "explicit file" True (optDryRun loaded)
  ]
