module ScanSpec (tests) where

import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (sort)
import System.FilePath ((</>))
import System.Posix.Files (createSymbolicLink, setFileTimes)

import HClean.Scan
import HClean.Types (Options (..), Target (..), defaultOptions)
import Harness

-- | Scan @root@ and return the matches as sorted @relative path -> pattern@.
matches :: Options -> FilePath -> [String] -> IO [(FilePath, String)]
matches o root patterns = do
  ts <- scan o root patterns
  pure (sort [(relativeTo root (targetPath t), targetPattern t) | t <- ts])

project :: [(FilePath, String)]
project =
  [ ("proj/__pycache__/a.pyc", "0123456789")
  , ("proj/sub/__pycache__/b.pyc", "01234")
  , ("proj/sub/keep.py", "x")
  , ("proj/.git/config", "x")
  , ("proj/.git/__pycache__/c.pyc", "x")
  , ("proj/package.json", "{}")
  , ("proj/dist/bundle.js", "xx")
  ]

tests :: TestGroup
tests = group "HClean.Scan"
  [ it "computes paths relative to the scan root" $ do
      assertEqual "nested" "a/b" (relativeTo "/tmp/root" "/tmp/root/a/b")
      assertEqual "root itself" "" (relativeTo "/tmp/root" "/tmp/root")
      assertEqual "normalised" "a" (relativeTo "/tmp/root/" "/tmp/root/./a")
  , it "matches files and directories anywhere in the tree" $
      withTree project $ \root ->
        assertEqual "pycache"
          [("proj/__pycache__", "**/__pycache__"), ("proj/sub/__pycache__", "**/__pycache__")]
          =<< matches defaultOptions root ["**/__pycache__"]
  , it "does not descend into a directory it already matched" $
      withTree project $ \root ->
        assertEqual "directory only, not its contents"
          [("proj/__pycache__", "**/__pycache__"), ("proj/sub/__pycache__", "**/__pycache__")]
          =<< matches defaultOptions root ["**/__pycache__", "**/*.pyc"]
  , it "never enters protected directories" $
      withTree project $ \root -> do
        found <- matches defaultOptions root ["**/config", "**/__pycache__"]
        assertBool "no .git contents" (all (notElem '/' . takeWhile (/= '/') . snd) found)
        assertEqual "only the two caches"
          [("proj/__pycache__", "**/__pycache__"), ("proj/sub/__pycache__", "**/__pycache__")]
          found
  , it "enters protected directories when protection is disabled" $
      withTree project $ \root -> do
        found <- matches defaultOptions { optNoProtect = True } root ["**/__pycache__"]
        assertBool "git cache found" (("proj/.git/__pycache__", "**/__pycache__") `elem` found)
  , it "prunes excluded paths" $
      withTree project $ \root ->
        assertEqual "sub excluded"
          [("proj/__pycache__", "**/__pycache__")]
          =<< matches defaultOptions { optExcludes = ["**/sub"] } root ["**/__pycache__"]
  , it "reports the first pattern that matched" $
      withTree project $ \root ->
        assertEqual "first wins"
          [("proj/__pycache__", "**/__pycache__"), ("proj/sub/__pycache__", "**/__pycache__")]
          =<< matches defaultOptions root ["**/__pycache__", "__pycache__"]
  , it "records sizes for files and zero for directories" $
      withTree project $ \root -> do
        ts <- scan defaultOptions root ["**/*.pyc", "**/__pycache__"]
        assertEqual "directories are sized later" [0, 0] (map targetSize ts)
        fs <- scan defaultOptions root ["**/a.pyc"]
        assertEqual "file size" [10] (map targetSize fs)
        assertEqual "is a directory" [True, True] . map targetIsDir =<< scan defaultOptions root ["**/__pycache__"]
  , it "only matches entries older than the age limit" $
      withTree project $ \root -> do
        setFileTimes (root </> "proj" </> "sub" </> "__pycache__") 1000000 1000000
        assertEqual "old one only"
          [("proj/sub/__pycache__", "**/__pycache__")]
          =<< matches defaultOptions { optOlderThan = Just 3600 } root ["**/__pycache__"]
  , it "ignores symlinks unless asked" $
      withTree project $ \root -> do
        createSymbolicLink (root </> "proj" </> "sub" </> "keep.py") (root </> "proj" </> "link.py")
        assertEqual "skipped" [] =<< matches defaultOptions root ["**/link.py"]
        assertEqual "included"
          [("proj/link.py", "**/link.py")]
          =<< matches defaultOptions { optSymlinks = True } root ["**/link.py"]
  , it "removes broken symlinks on request" $
      withTree project $ \root -> do
        createSymbolicLink (root </> "proj" </> "nowhere") (root </> "proj" </> "dangling")
        createSymbolicLink (root </> "proj" </> "package.json") (root </> "proj" </> "intact")
        assertEqual "only the dangling one"
          [("proj/dangling", "broken-symlink")]
          =<< matches defaultOptions { optBrokenSymlinks = True } root ["**/nothing"]
  , it "detects build artifacts next to a project marker" $
      withTree (project ++ [("proj/.git/HEAD", "ref"), ("plain/dist/x.js", "x")]) $ \root ->
        assertEqual "dist only inside the repo"
          [("proj/dist", "build-artifact")]
          =<< matches defaultOptions { optArtifacts = True } root ["**/nothing"]
  , it "requires the marker file, not just a repository" $
      withTree [("proj/.git/HEAD", "ref"), ("proj/target/x.o", "x")] $ \root ->
        assertEqual "no Cargo.toml, no match"
          []
          =<< matches defaultOptions { optArtifacts = True } root ["**/nothing"]
  , it "terminates on symlink loops" $
      withTree [("a/b/x.pyc", "1")] $ \root -> do
        createSymbolicLink (root </> "a") (root </> "a" </> "b" </> "loop")
        assertEqual "loop is not followed"
          [("a/b/x.pyc", "**/*.pyc")]
          =<< matches defaultOptions { optSymlinks = True } root ["**/*.pyc"]
  , it "reports visits and matches to the hooks" $
      withTree [("a/x.pyc", "1"), ("a/y.txt", "2")] $ \root -> do
        visited <- newIORef []
        matched <- newIORef []
        let hooks = ScanHooks
              { onVisit = \p -> modifyIORef' visited (relativeTo root p :)
              , onMatch = \t -> modifyIORef' matched (targetPattern t :)
              }
        _ <- scanWith hooks defaultOptions root ["**/*.pyc"]
        assertEqual "every entry" ["a", "a/x.pyc", "a/y.txt"] . reverse =<< readIORef visited
        assertEqual "only matches" ["**/*.pyc"] . reverse =<< readIORef matched
  , it "measures directory trees" $
      withTree [("d/a", "12345"), ("d/e/b", "123"), ("d/e/f/c", "1")] $ \root ->
        assertEqual "recursive size" 9 =<< directorySize (root </> "d")
  , it "survives unreadable directories" $
      withTree [("a/x.pyc", "1")] $ \root ->
        assertEqual "missing directory is empty" 0 =<< directorySize (root </> "nope")
  ]
