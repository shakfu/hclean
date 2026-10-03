module ConfigSpec (tests) where

import Data.List (isInfixOf)
import System.Directory (doesPathExist, withCurrentDirectory)
import System.FilePath ((</>), takeDirectory)
import System.Posix.Files (createSymbolicLink)

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

-- | 'applyConfig', failing the test on an error.
apply :: FilePath -> Options -> IO Options
apply path o = either assertFailure pure =<< applyConfig path o

-- | 'resolveConfig', failing the test on an error.
resolved :: ConfigSource -> Options -> IO Options
resolved source o = either assertFailure pure =<< resolveConfig source o

-- | The error 'applyConfig' reports, failing the test if there is none.
applyError :: FilePath -> Options -> IO String
applyError path o = either pure (const (assertFailure "expected an error")) =<< applyConfig path o

withConfig :: String -> (FilePath -> IO a) -> IO a
withConfig text action = withTree [(".hclean.toml", text)] (action . (</> ".hclean.toml"))

tests :: TestGroup
tests = group "HClean.Config"
  [ it "reads every supported key" $
      withTree [(".hclean.toml", configText)] $ \root -> do
        o <- apply (root </> ".hclean.toml") defaultOptions
        assertEqual "path" (Just "/srv/project") (optRoot o)
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
      withTree [(".hclean.toml", "path = \".\"\n")] $ \root -> do
        o <- apply (root </> ".hclean.toml") defaultOptions
        assertEqual "unquoted" (Just root) (optRoot o)
  , it "reads literal strings without escapes" $
      withConfig "path = 'a\\b'\n" $ \file -> do
        o <- apply file defaultOptions
        assertEqual "literal" (Just (takeDirectory file </> "a\\b")) (optRoot o)
  , it "ignores comments" $
      withConfig "# heading\npath = \".\" # trailing\npatterns = [\"a#b\"] # x\ndry_run = true # y\n" $ \file -> do
        o <- apply file defaultOptions
        assertEqual "path" (Just (takeDirectory file)) (optRoot o)
        assertEqual "hash inside a string" ["a#b"] (optIncludes o)
        assertEqual "flag" True (optDryRun o)
  , it "resolves a relative path against the file's directory" $
      withTree [("a/.hclean.toml", "path = \"src\"\n")] $ \root -> do
        o <- apply (root </> "a" </> ".hclean.toml") defaultOptions
        assertEqual "beside the file" (Just (root </> "a" </> "src")) (optRoot o)
        rel <- withCurrentDirectory root (apply ("a" </> ".hclean.toml") defaultOptions)
        assertEqual "file named relatively" (Just ("a" </> "src")) (optRoot rel)
  , it "resolves the global file's path against the working directory" $
      withTree [(".config/hclean/config.toml", "path = \".\"\n"), ("work/", "")] $ \root -> do
        o <- withHome root $ withEnv "XDG_CONFIG_HOME" Nothing $
               withCurrentDirectory (root </> "work") $ resolved DiscoverConfig defaultOptions
        assertEqual "left relative" (Just ".") (optRoot o)
  , it "reads the global file from an absolute XDG_CONFIG_HOME" $
      withTree [ ("xdg/hclean/config.toml", "dry_run = true\n")
               , (".config/hclean/config.toml", "stats_mode = true\n"), ("work/", "") ] $ \root ->
        withHome root $ withCurrentDirectory (root </> "work") $ do
          o <- withEnv "XDG_CONFIG_HOME" (Just (root </> "xdg")) $ resolved DiscoverConfig defaultOptions
          assertEqual "XDG file" (True, False) (optDryRun o, optStats o)
          r <- withEnv "XDG_CONFIG_HOME" (Just "xdg") $ resolved DiscoverConfig defaultOptions
          assertEqual "relative value ignored" (False, True) (optDryRun r, optStats r)
  , it "does not discover a file in or above the home directory" $
      withTree [ (".hclean.toml", "dry_run = true\n"), ("home/.hclean.toml", "dry_run = true\n")
               , ("home/proj/a/", "") ] $ \root ->
        withHome (root </> "home") $ do
          found <- discoverConfig (root </> "home" </> "proj" </> "a")
          assertEqual "neither file" Nothing found
          atHome <- discoverConfig (root </> "home")
          assertEqual "not from home itself" Nothing atHome
  , it "discovers a project file below the home directory" $
      withTree [("home/.hclean.toml", ""), ("home/proj/.hclean.toml", ""), ("home/proj/a/", "")] $ \root ->
        withHome (root </> "home") $ do
          found <- discoverConfig (root </> "home" </> "proj" </> "a")
          assertEqual "project file" (Just (root </> "home" </> "proj" </> ".hclean.toml")) found
  , it "searches to the root when started outside the home directory" $
      withTree [(".hclean.toml", ""), ("home/", ""), ("work/a/", "")] $ \root ->
        withHome (root </> "home") $ do
          found <- discoverConfig (root </> "work" </> "a")
          assertEqual "ancestor" (Just (root </> ".hclean.toml")) found
  , it "matches keys exactly, not by prefix" $
      withConfig "path_style = \"x\"\n" $ \file -> do
        o <- apply file defaultOptions
        assertEqual "unset" Nothing (optRoot o)
  , it "stops at the first table header" $
      withConfig "dry_run = true\n[other]\npath = \"x\"\n" $ \file -> do
        o <- apply file defaultOptions
        assertEqual "table key ignored" Nothing (optRoot o)
        assertEqual "top level read" True (optDryRun o)
  , it "rejects values of the wrong type" $ do
      withConfig "dry_run = \"yes\"\n" $ \file ->
        assertEqual "message" (file ++ ": dry_run must be a boolean") =<< applyError file defaultOptions
      withConfig "path = .\n" $ \file ->
        assertEqual "bare word" (file ++ ": line 1: expected a string, boolean or array")
          =<< applyError file defaultOptions
  , it "reports a missing file" $
      withTree [] $ \root -> do
        err <- applyError (root </> "nope.toml") defaultOptions
        assertBool ("names the file: " ++ err) ("nope.toml" `isInfixOf` err)
  , it "lets command line lists and path win over the file" $
      withTree [(".hclean.toml", configText)] $ \root -> do
        o <- apply (root </> ".hclean.toml")
               defaultOptions { optRoot = Just "here", optIncludes = ["**/*.bak"], optPresets = ["node"] }
        assertEqual "path" (Just "here") (optRoot o)
        assertEqual "patterns" ["**/*.bak"] (optIncludes o)
        assertEqual "presets" ["node"] (optPresets o)
  , it "treats absent flags as off and never turns one off" $
      withTree [(".hclean.toml", "dry_run = false\n")] $ \root -> do
        o <- apply (root </> ".hclean.toml") defaultOptions { optDryRun = True }
        assertEqual "still on" True (optDryRun o)
        o2 <- apply (root </> ".hclean.toml") defaultOptions
        assertEqual "off" False (optDryRun o2)
  , it "finds the nearest config file walking upwards" $
      withTree [(".hclean.toml", "path = \".\"\n"), ("a/b/c/", "")] $ \root -> do
        found <- discoverConfig (root </> "a" </> "b" </> "c")
        assertEqual "ancestor" (Just (root </> ".hclean.toml")) found
  , it "prefers the closest config file" $
      withTree [(".hclean.toml", ""), ("a/.hclean.toml", ""), ("a/b/", "")] $ \root -> do
        found <- discoverConfig (root </> "a" </> "b")
        assertEqual "closest" (Just (root </> "a" </> ".hclean.toml")) found
  , it "discovers from the working directory" $
      withTree [(".hclean.toml", "dry_run = true\n"), ("a/b/", "")] $ \root ->
        withCurrentDirectory (root </> "a" </> "b") $ do
          o <- resolved DiscoverConfig defaultOptions
          assertEqual "found in an ancestor" True (optDryRun o)
  , it "writes a starter config and refuses to overwrite" $
      withTree [] $ \root -> withCurrentDirectory root $ do
        written <- writeDefaultConfig configFileName
        assertEqual "written" True written
        contents <- readFile configFileName
        assertEqual "contents" defaultConfigContents contents
        _ <- apply configFileName defaultOptions
        again <- writeDefaultConfig configFileName
        assertEqual "refused" False again
  , it "refuses to write through a dangling symlink" $
      withTree [] $ \root -> withCurrentDirectory root $ do
        createSymbolicLink (root </> "elsewhere") configFileName
        assertEqual "refused" False =<< writeDefaultConfig configFileName
        assertBool "target not created" . not =<< doesPathExist (root </> "elsewhere")
  , it "resolves the requested source" $
      withTree [(".hclean.toml", "dry_run = true\n")] $ \root -> do
        untouched <- resolveConfig NoConfig defaultOptions
        assertEqual "no config" (Right defaultOptions) untouched
        loaded <- resolved (ConfigFile (root </> ".hclean.toml")) defaultOptions
        assertEqual "explicit file" True (optDryRun loaded)
  ]
