-- | A very small test harness, so the test suite needs no extra dependencies.
module Harness
  ( TestCase
  , TestGroup
  , it
  , group
  , runSuite
  , assertEqual
  , assertBool
  , assertFailure
  , withTree
  ) where

import Control.Exception (IOException, SomeException, bracket, displayException, fromException, try)
import Control.Monad (forM_, unless)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (isSuffixOf)
import System.Directory
  (createDirectoryIfMissing, doesPathExist, getTemporaryDirectory, removePathForcibly)
import System.Exit (exitFailure)
import System.FilePath ((</>), takeDirectory)
import System.IO.Error (ioeGetErrorString, isUserError)
import System.Posix.Process (getProcessID)

-- | A named check that fails by throwing.
data TestCase = TestCase String (IO ())

-- | Named collection of checks.
data TestGroup = TestGroup String [TestCase]

it :: String -> IO () -> TestCase
it = TestCase

group :: String -> [TestCase] -> TestGroup
group = TestGroup

-- | Run every group, report failures and exit non-zero if there were any.
runSuite :: [TestGroup] -> IO ()
runSuite groups = do
  failures <- newIORef (0 :: Int)
  total <- newIORef (0 :: Int)
  forM_ groups $ \(TestGroup name cases) -> do
    putStrLn name
    forM_ cases $ \(TestCase label action) -> do
      modifyIORef' total (+ 1)
      outcome <- try action
      case outcome of
        Right () -> putStrLn ("  ok    " ++ label)
        Left err -> do
          modifyIORef' failures (+ 1)
          putStrLn ("  FAIL  " ++ label)
          putStrLn (indent (describe err))
  bad <- readIORef failures
  n <- readIORef total
  putStrLn ""
  putStrLn (show (n - bad) ++ "/" ++ show n ++ " tests passed")
  unless (bad == 0) exitFailure
  where
    -- Assertion failures carry only their message; anything else is a crash.
    describe :: SomeException -> String
    describe err = case fromException err of
      Just ioe | isUserError ioe -> ioeGetErrorString ioe
      _ -> displayException err

    indent = init . unlines . map ("        " ++) . lines

assertFailure :: String -> IO a
assertFailure = ioError . userError

assertBool :: String -> Bool -> IO ()
assertBool label ok = unless ok (assertFailure label)

-- | @assertEqual label expected actual@
assertEqual :: (Eq a, Show a) => String -> a -> a -> IO ()
assertEqual label expected actual =
  unless (expected == actual) $
    assertFailure (label ++ "\n      expected: " ++ show expected
                         ++ "\n      actual:   " ++ show actual)

-- | Populate a fresh temporary directory and hand its path to the action.
--
-- Entries ending in @\/@ become directories, everything else a file with the
-- given contents; parent directories are created as needed.
withTree :: [(FilePath, String)] -> (FilePath -> IO a) -> IO a
withTree entries action = bracket create removePathForcibly action
  where
    create = do
      tmp <- getTemporaryDirectory
      pid <- getProcessID
      root <- freshName [tmp </> ("hclean-test-" ++ show pid ++ "-" ++ show n) | n <- [0 :: Int ..]]
      createDirectoryIfMissing True root
      forM_ entries $ \(path, contents) ->
        if "/" `isSuffixOf` path
          then createDirectoryIfMissing True (root </> path)
          else do
            createDirectoryIfMissing True (takeDirectory (root </> path))
            writeFile (root </> path) contents
      pure root

    freshName [] = assertFailure "no free temporary directory name"
    freshName (c : cs) = do
      taken <- doesPathExist c
      if taken then freshName cs else pure c
