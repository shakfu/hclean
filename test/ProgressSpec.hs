module ProgressSpec (tests) where

import Control.Exception (bracket, bracket_)
import Control.Monad (forM_)
import GHC.IO.Handle (hDuplicate, hDuplicateTo)
import System.FilePath ((</>))
import System.IO

import Harness
import Progress

-- | Run an action with stderr pointed at a file and return what it wrote.
--
-- The redirected handle is not a terminal, which is also the case the
-- indicator has to stay quiet in.
captureStderr :: IO a -> IO (String, a)
captureStderr action =
  withTree [] $ \dir -> do
    let path = dir </> "stderr"
    saved <- hDuplicate stderr
    result <- bracket_ (redirect path) (restore saved) action
    written <- readFile' path
    pure (written, result)
  where
    redirect path = do
      h <- openFile path WriteMode
      hDuplicateTo h stderr
      hClose h
    restore saved = do
      hFlush stderr
      hDuplicateTo saved stderr
      hClose saved
    readFile' path = bracket (openFile path ReadMode) hClose $ \h -> do
      contents <- hGetContents h
      length contents `seq` pure contents

tests :: TestGroup
tests = group "Progress"
  [ it "turns the spinner" $ do
      assertEqual "frames" "|/-\\|" (map spinnerFrame [0 .. 4])
  , it "keeps the informative end of a path" $ do
      assertEqual "short enough" "a/b/c" (shorten 10 "a/b/c")
      assertEqual "exact fit" "a/b/c" (shorten 5 "a/b/c")
      assertEqual "clipped" ".../d/e" (shorten 7 "/a/b/c/d/e")
      assertEqual "no room" "" (shorten 0 "/a/b")
      assertEqual "almost no room" ".." (shorten 2 "/a/b")
  , it "lays out the indicator line" $ do
      assertEqual "with path"
        "| scanning, 12 entries  /tmp/x"
        (indicatorLine 80 '|' "scanning, 12 entries" "/tmp/x")
      assertEqual "path dropped when there is no room"
        "/ scanning, 12 entries"
        (indicatorLine 25 '/' "scanning, 12 entries" "/tmp/some/deep/path")
      assertEqual "path clipped to the width"
        "| working  .../deep/path"
        (indicatorLine 24 '|' "working" "/tmp/some/deep/path")
      assertEqual "message clipped to the width"
        "| scanni"
        (indicatorLine 8 '|' "scanning, 12 entries" "")
  , it "stays silent when stderr is not a terminal" $ do
      (written, ()) <- captureStderr $
        withProgress ProgressAuto (const "scanning") (const (Just "done")) $ \p ->
          forM_ [1 .. 10 :: Int] (\n -> progressTick p ("/tmp/" ++ show n))
      assertEqual "nothing painted" "" written
  , it "says nothing at all when disabled" $ do
      (written, ()) <- captureStderr $
        withProgress ProgressNever (const "scanning") (const (Just "done")) $ \p ->
          progressTick p "/tmp/x"
      assertEqual "silent" "" written
  , it "summarises off a terminal when progress is forced" $ do
      (written, ()) <- captureStderr $
        withProgress ProgressAlways (const "scanning") (\n -> Just ("scanned " ++ show n ++ " entries")) $ \p ->
          forM_ [1 .. 3 :: Int] (\n -> progressTick p ("/tmp/" ++ show n))
      assertEqual "one summary line" "scanned 3 entries\n" written
  , it "omits the summary when there is none to give" $ do
      (written, ()) <- captureStderr $
        withProgress ProgressAlways (const "removing") (const Nothing) $ \p ->
          progressTick p "/tmp/x"
      assertEqual "quiet" "" written
  , it "prints notes whatever the mode" $ do
      (written, ()) <- captureStderr $
        withProgress ProgressNever (const "scanning") (const Nothing) $ \p -> do
          progressNote p "root: /tmp"
          progressNote p "match: /tmp/x"
      assertEqual "both lines" "root: /tmp\nmatch: /tmp/x\n" written
  , it "returns the action's result" $ do
      (_, value) <- captureStderr $
        withProgress ProgressNever (const "scanning") (const Nothing) (const (pure (42 :: Int)))
      assertEqual "passed through" 42 value
  ]
