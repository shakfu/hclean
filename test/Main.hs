-- | Entry point for the hclean test suite.
module Main (main) where

import qualified CLISpec
import qualified ConfigSpec
import qualified GlobSpec
import qualified PresetSpec
import qualified ProgressSpec
import qualified ReportSpec
import qualified ScanSpec
import qualified UtilSpec

import Harness (runSuite)

main :: IO ()
main = runSuite
  [ GlobSpec.tests
  , UtilSpec.tests
  , PresetSpec.tests
  , ProgressSpec.tests
  , ReportSpec.tests
  , ConfigSpec.tests
  , ScanSpec.tests
  , CLISpec.tests
  ]
