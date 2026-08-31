module UtilSpec (tests) where

import HClean.Util (parseDuration, trim)
import Harness

tests :: TestGroup
tests = group "HClean.Util"
  [ it "parses each duration unit" $ do
      assertEqual "seconds" (Right 45) (parseDuration "45s")
      assertEqual "minutes" (Right 1800) (parseDuration "30m")
      assertEqual "hours" (Right 43200) (parseDuration "12h")
      assertEqual "days" (Right 259200) (parseDuration "3d")
      assertEqual "weeks" (Right 1209600) (parseDuration "2w")
  , it "keeps multi-digit numbers in order" $ do
      assertEqual "12m is twelve minutes" (Right 720) (parseDuration "12m")
      assertEqual "101s" (Right 101) (parseDuration "101s")
  , it "ignores surrounding whitespace" $
      assertEqual "padded" (Right 60) (parseDuration "  1m ")
  , it "rejects malformed durations" $ do
      assertEqual "no unit" (Left "duration must be a number followed by a unit") (parseDuration "30")
      assertEqual "no digits" (Left "duration must be a number followed by a unit") (parseDuration "m")
      assertEqual "empty" (Left "duration must be a number followed by a unit") (parseDuration "")
      assertEqual "bad unit" (Left "duration unit must be s, m, h, d, or w") (parseDuration "30y")
  , it "trims whitespace" $ do
      assertEqual "both ends" "x y" (trim "  x y \t")
      assertEqual "nothing to do" "x" (trim "x")
  ]
