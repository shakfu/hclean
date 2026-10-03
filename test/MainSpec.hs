-- | End-to-end tests of the built @hclean@ executable, which cabal puts on
-- @PATH@ through @build-tool-depends@.
module MainSpec (tests) where

import Control.Exception (finally)
import Data.List (isInfixOf)
import System.Directory (canonicalizePath, doesPathExist, findExecutable)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO (IOMode (..), char8, hGetContents, hSetEncoding, withFile)
import System.Posix.Files (setFileMode)
import System.Posix.Process (ProcessStatus (..), executeFile, forkProcess, getProcessStatus)
import System.Posix.User (getEffectiveUserID)

import Harness

data Outcome = Outcome
  { code :: Int
  , out  :: String
  , err  :: String
  }

-- | Run @hclean args@ in @cwd@ with @input@ on stdin. Output is read as bytes.
run :: String -> FilePath -> [String] -> IO Outcome
run input cwd args = do
  binary <- maybe (assertFailure "hclean is not on PATH; run the suite with cabal test") pure
              =<< findExecutable "hclean"
  withTree [("in", input)] $ \tmp -> do
    let command = unwords
          [ "cd", quote cwd, "&&", unwords (map quote (binary : args))
          , "<", quote (tmp </> "in"), ">", quote (tmp </> "out"), "2>", quote (tmp </> "err") ]
    status <- shell command
    Outcome status <$> bytes (tmp </> "out") <*> bytes (tmp </> "err")
  where
    bytes path = withFile path ReadMode $ \h -> do
      hSetEncoding h char8
      s <- hGetContents h
      length s `seq` pure s

-- | Run a command with @\/bin\/sh@ and return its exit status.
shell :: String -> IO Int
shell command = do
  pid <- forkProcess (executeFile "/bin/sh" False ["-c", command] Nothing)
  status <- getProcessStatus True False pid
  case status of
    Just (Exited ExitSuccess)     -> pure 0
    Just (Exited (ExitFailure n)) -> pure n
    other -> assertFailure ("unexpected process status: " ++ show other)

quote :: String -> String
quote s = "'" ++ concatMap (\c -> if c == '\'' then "'\\''" else [c]) s ++ "'"

-- | 'withTree', with the root resolved as the executable will see it.
withRoot :: [(FilePath, String)] -> (FilePath -> IO a) -> IO a
withRoot entries action = withTree entries (\root -> action =<< canonicalizePath root)

tree :: [(FilePath, String)]
tree = [("p/a/__pycache__/x.pyc", "1"), ("p/b.pyc", "22"), ("p/keep.py", "3")]

tests :: TestGroup
tests = group "Main"
  [ it "previews without removing" $
      withRoot tree $ \root -> do
        r <- run "" root ["-p", "p", "-d"]
        assertEqual "exit" 0 (code r)
        assertEqual "listing"
          ("Matched: " ++ root </> "p/a/__pycache__\nMatched: " ++ root </> "p/b.pyc\n")
          (out r)
        assertBool "untouched" =<< doesPathExist (root </> "p/b.pyc")
  , it "prompts on stderr with the count, and removes only after a yes" $
      withRoot tree $ \root -> do
        r <- run "n\n" root ["-p", "p"]
        assertEqual "exit" 0 (code r)
        assertBool ("prompted: " ++ err r) ("Delete 2 item(s)? [y/N]" `isInfixOf` err r)
        assertBool "not on stdout" (not ("Delete" `isInfixOf` out r))
        assertBool "declined" =<< doesPathExist (root </> "p/b.pyc")
        q <- run "Y\n" root ["-p", "p", "-q"]
        assertEqual "exit" 0 (code q)
        assertEqual "quiet" "" (out q)
        assertBool ("quiet prompt states the count: " ++ err q) ("Delete 2 item(s)?" `isInfixOf` err q)
        assertBool "removed" . not =<< doesPathExist (root </> "p/b.pyc")
        assertBool "kept" =<< doesPathExist (root </> "p/keep.py")
  , it "reports what removal freed" $
      withRoot tree $ \root -> do
        r <- run "" root ["-p", "p", "-y"]
        assertEqual "exit" 0 (code r)
        assertBool ("summary line: " ++ out r) ("Removed 2 item(s), 3 B.\n" `isInfixOf` out r)
        j <- run "" root ["-p", "p", "-y", "--format", "json", "-g", "keep.py"]
        assertBool ("JSON: " ++ out j) ("\"freed_size\":1," `isInfixOf` out j)
  , it "prints I/O errors without a backtrace" $ do
      uid <- getEffectiveUserID
      if uid == 0 then pure () else
        withRoot [("ro/", "")] $ \root -> do
          setFileMode (root </> "ro") 0o555
          r <- run "" (root </> "ro") ["-w"] `finally` setFileMode (root </> "ro") 0o755
          assertEqual "exit" 1 (code r)
          assertBool ("prefixed: " ++ err r) ("hclean: .hclean.toml" `isInfixOf` err r)
          assertBool "no backtrace" (not ("CallStack" `isInfixOf` err r))
  , it "writes the config file into --path" $
      withRoot [("sub/", "")] $ \root -> do
        r <- run "" root ["-w", "-p", "sub"]
        assertEqual ("exit: " ++ err r) 0 (code r)
        assertBool "in sub" =<< doesPathExist (root </> "sub/.hclean.toml")
        assertBool "not in cwd" . not =<< doesPathExist (root </> ".hclean.toml")
        again <- run "" root ["-w", "-p", "sub"]
        assertEqual "refused" 1 (code again)
        assertEqual "names the file" "hclean: Cannot overwrite existing 'sub/.hclean.toml' file\n" (err again)
        missing <- run "" root ["-w", "-p", "nope"]
        assertEqual "missing exit" 1 (code missing)
        assertEqual "missing" "hclean: invalid path: nope\n" (err missing)
  , it "treats end of input as no" $
      withRoot tree $ \root -> do
        r <- run "" root ["-p", "p"]
        assertEqual "exit" 0 (code r)
        assertBool "kept" =<< doesPathExist (root </> "p/b.pyc")
  , it "reports failed removals and keeps going" $ do
      uid <- getEffectiveUserID
      if uid == 0 then pure () else
        withRoot [("t/ro/__pycache__/x.pyc", "1"), ("t/rw/__pycache__/y.pyc", "2")] $ \root -> do
          let ro = root </> "t/ro"
          setFileMode ro 0o555
          (j, t) <- (do
              j <- run "" root ["-p", "t", "-y", "--format", "json"]
              t <- run "" root ["-p", "t", "-y"]
              pure (j, t)) `finally` setFileMode ro 0o755
          assertEqual "exit" 1 (code j)
          assertBool ("failure in JSON: " ++ out j)
            (("\"failures\":[{\"path\":\"" ++ ro </> "__pycache__\"") `isInfixOf` out j)
          assertBool "later target removed" . not =<< doesPathExist (root </> "t/rw/__pycache__")
          assertEqual "text exit" 1 (code t)
          assertBool ("names the failure: " ++ err t) (("hclean: " ++ ro </> "__pycache__") `isInfixOf` err t)
          assertBool "no backtrace" (not ("CallStack" `isInfixOf` err t))
  , it "discovers configuration in an ancestor of the working directory" $
      withRoot [(".hclean.toml", "patterns = [\"**/*.marker\"]\n"), ("n/d/x.marker", "")] $ \root -> do
        r <- run "" (root </> "n/d") ["-c", "-d"]
        assertEqual "found" ("Matched: " ++ root </> "n/d/x.marker\n") (out r)
  , it "scans the config file's directory from a subdirectory" $
      withRoot [(".hclean.toml", "path = \".\"\npatterns = [\"**/*.marker\"]\n"), ("top.marker", ""), ("n/d/", "")] $ \root -> do
        r <- run "" (root </> "n/d") ["-c", "-d"]
        assertEqual "whole tree" ("Matched: " ++ root </> "top.marker\n") (out r)
  , it "lets --path override the config file's path" $
      withRoot ((".hclean.toml", "path = \"missing\"\n") : tree) $ \root -> do
        r <- run "" root ["-c", "-p", "p", "-d", "-g", "**/b.pyc"]
        assertEqual ("exit: " ++ err r) 0 (code r)
        assertEqual "scanned p" ("Matched: " ++ root </> "p/b.pyc\n") (out r)
  , it "lists the patterns a run would use" $
      withRoot [] $ \root -> do
        r <- run "" root ["-g", "**/*.log", "--preset", "rust", "-l"]
        assertEqual "includes and presets" "**/*.log\n**/target\n" (out r)
  , it "rejects bad input before scanning" $
      withRoot [(".hclean.toml", "dry_run = \"yes\"\n")] $ \root -> do
        e <- run "" root ["-e", "[x"]
        assertEqual "exit" 1 (code e)
        assertEqual "exclude" "hclean: invalid glob pattern: [x\n" (err e)
        c <- run "" root ["-c"]
        assertEqual "config exit" 1 (code c)
        assertEqual "config" ("hclean: " ++ root </> ".hclean.toml: dry_run must be a boolean\n") (err c)
  , it "prints file names that are not valid UTF-8" $
      withRoot [("d/", "")] $ \root -> do
        -- APFS refuses such names, so the check only runs where they exist.
        _ <- shell ("touch " ++ quote (root </> "d") ++ "/\"$(printf '\\377\\376.pyc')\" 2>/dev/null")
        made <- (== 0) <$> shell ("ls " ++ quote (root </> "d") ++ " | grep -q pyc")
        if not made then pure () else do
          r <- run "" root ["-p", "d", "-d", "-g", "*.pyc"]
          assertEqual ("exit: " ++ err r) 0 (code r)
          assertBool ("raw bytes: " ++ out r) ("/\255\254.pyc\n" `isInfixOf` out r)
  ]
