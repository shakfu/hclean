module DeleteSpec (tests) where

import Control.Exception (finally)
import Data.List (isInfixOf)
import System.Directory (doesPathExist, listDirectory)
import System.FilePath ((</>))
import System.Posix.Files (createSymbolicLink, setFileMode)
import System.Posix.User (getEffectiveUserID)

import HClean.Delete
import HClean.Types (Target (..))
import Harness

target :: FilePath -> Target
target p = Target p False "x" 0

tests :: TestGroup
tests = group "HClean.Delete"
  [ it "removes files and directory trees" $
      withTree [("d/a", "1"), ("d/e/b", "2"), ("f", "3")] $ \root -> do
        (failures, freed) <- removeTargets (const (pure ())) [target (root </> "d"), target (root </> "f")]
        assertEqual "no failures" [] failures
        assertEqual "file bytes freed" 3 freed
        assertBool "directory gone" . not =<< doesPathExist (root </> "d")
        assertBool "file gone" . not =<< doesPathExist (root </> "f")
  , it "counts the bytes it frees" $
      withTree [("d/a", "123"), ("d/e/b", "12345"), ("f", "1")] $ \root -> do
        (_, freed) <- removeTargets (const (pure ())) [target (root </> "d"), target (root </> "f")]
        assertEqual "file bytes only" 9 freed
  , it "removes a symlink, not what it points to" $
      withTree [("real/keep", "1")] $ \root -> do
        createSymbolicLink (root </> "real") (root </> "link")
        assertEqual "removed" Nothing =<< removePath (root </> "link")
        assertBool "target intact" =<< doesPathExist (root </> "real" </> "keep")
  , it "continues past a failed removal" $ do
      uid <- getEffectiveUserID
      -- root ignores directory permissions, so the failure cannot be staged
      if uid == 0 then pure () else
        withTree [("ro/__pycache__/x.pyc", "1"), ("rw/__pycache__/y.pyc", "2")] $ \root -> do
          let ro = root </> "ro"
          setFileMode ro 0o555
          (failures, freed) <- removeTargets (const (pure ()))
                        [target (ro </> "__pycache__"), target (root </> "rw" </> "__pycache__")]
                        `finally` setFileMode ro 0o755
          assertEqual "one failure" [ro </> "__pycache__"] (map (targetPath . failureTarget) failures)
          assertBool "names the cause" (all (("ermission denied" `isInfixOf`) . failureError) failures)
          assertBool "later target removed" . not =<< doesPathExist (root </> "rw" </> "__pycache__")
          -- x.pyc goes before its directory fails, so both one-byte files count
          assertEqual "only removed bytes counted" 2 freed
          assertEqual "failed target emptied" [] =<< listDirectory (ro </> "__pycache__")
  , it "reports a missing path" $
      withTree [] $ \root -> do
        result <- removePath (root </> "nope")
        assertBool "error" (result /= Nothing)
  ]
