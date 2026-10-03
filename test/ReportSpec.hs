module ReportSpec (tests) where

import Data.List (isInfixOf)

import HClean.Delete (Failure (..))
import HClean.Report
import HClean.Types (Target (..))
import Harness

sample :: [Target]
sample =
  [ Target "/tmp/p/.DS_Store" False "**/.DS_Store" 0
  , Target "/tmp/p/__pycache__" True "**/__pycache__" 5000
  , Target "/tmp/p/other/__pycache__" True "**/__pycache__" 1000
  ]

summary :: Summary
summary = Summary
  { summaryTargets = sample
  , summaryTotalSize = 6000
  , summaryStats =
      [ PatternStat "**/.DS_Store" 1 0
      , PatternStat "**/__pycache__" 2 6000
      ]
  }

tests :: TestGroup
tests = group "HClean.Report"
  [ it "formats byte counts with binary units" $ do
      assertEqual "zero" "0 B" (formatSize 0)
      assertEqual "bytes" "100 B" (formatSize 100)
      assertEqual "exact KiB" "1.00 KiB" (formatSize 1024)
      assertEqual "fractional KiB" "4.88 KiB" (formatSize 5000)
      assertEqual "rounded KiB" "4.98 KiB" (formatSize 5100)
      assertEqual "MiB" "1.00 MiB" (formatSize 1048576)
      assertEqual "GiB" "2.50 GiB" (formatSize 2684354560)
      assertEqual "TiB" "1.00 TiB" (formatSize 1099511627776)
  , it "lists matches as text" $
      assertEqual "listing"
        "Matched: /tmp/p/.DS_Store\n\
        \Matched: /tmp/p/__pycache__\n\
        \Matched: /tmp/p/other/__pycache__\n"
        (renderText False summary)
  , it "appends statistics when asked" $
      assertEqual "with stats"
        "Matched: /tmp/p/.DS_Store\n\
        \Matched: /tmp/p/__pycache__\n\
        \Matched: /tmp/p/other/__pycache__\n\
        \  **/.DS_Store: 1 item(s), 0 B\n\
        \  **/__pycache__: 2 item(s), 5.86 KiB\n"
        (renderText True summary)
  , it "renders an empty report" $
      assertEqual "nothing" "" (renderText True (Summary [] 0 []))
  , it "renders JSON with matches, summary and stats" $ do
      let out = renderJson True [] 0 summary
      assertBool "matches" ("\"matches\":[{\"path\":\"/tmp/p/.DS_Store\"" `isInfixOf` out)
      assertBool "size" ("\"size\":5000" `isInfixOf` out)
      assertBool "count" ("\"total_count\":3" `isInfixOf` out)
      assertBool "total" ("\"total_size\":6000" `isInfixOf` out)
      assertBool "human" ("\"total_size_human\":\"5.86 KiB\"" `isInfixOf` out)
      assertBool "dry run" ("\"dry_run\":true" `isInfixOf` out)
      assertBool "stats" ("\"count\":2" `isInfixOf` out)
      assertBool "failures" ("\"failures\":[]" `isInfixOf` out)
  , it "lists removal failures in JSON" $ do
      let out = renderJson False [Failure (Target "/tmp/p/.DS_Store" False "**/.DS_Store" 0) "permission denied"] 0 summary
      assertBool "failure"
        ("\"failures\":[{\"path\":\"/tmp/p/.DS_Store\",\"error\":\"permission denied\"}]" `isInfixOf` out)
  , it "reports the bytes freed" $ do
      let out = renderJson False [] 1536 summary
      assertBool "bytes" ("\"freed_size\":1536" `isInfixOf` out)
      assertBool "human" ("\"freed_size_human\":\"1.50 KiB\"" `isInfixOf` out)
      assertEqual "text" "Removed 2 item(s), 1.50 KiB.\n" (renderRemoved 2 1536)
  , it "reports dry_run as false when deleting" $
      assertBool "false" ("\"dry_run\":false" `isInfixOf` renderJson False [] 0 summary)
  , it "escapes JSON strings" $ do
      let out = renderJson False [] 0 (Summary [Target "a\"b\\c\nd\te" False "\SOH" 0] 0 [])
      assertBool "quote" ("a\\\"b" `isInfixOf` out)
      assertBool "backslash" ("b\\\\c" `isInfixOf` out)
      assertBool "newline" ("c\\nd" `isInfixOf` out)
      assertBool "tab" ("d\\te" `isInfixOf` out)
      assertBool "control character" ("\\u0001" `isInfixOf` out)
      assertBool "no raw control character" (not ("\SOH" `isInfixOf` out))
  , it "measures directories when summarising" $
      withTree [("cache/a.pyc", "0123456789"), ("cache/deep/b.pyc", "01234"), ("loose.txt", "xy")] $ \root -> do
        s <- summarize True
          [ Target (root ++ "/cache") True "**/cache" 0
          , Target (root ++ "/loose.txt") False "*.txt" 2
          ]
        assertEqual "directory size" [15, 2] (map targetSize (summaryTargets s))
        assertEqual "total" 17 (summaryTotalSize s)
        assertEqual "stats"
          [PatternStat "**/cache" 1 15, PatternStat "*.txt" 1 2]
          (summaryStats s)
  , it "leaves directories unmeasured when asked" $
      withTree [("cache/a.pyc", "0123456789")] $ \root -> do
        s <- summarize False [Target (root ++ "/cache") True "**/cache" 0]
        assertEqual "unmeasured" 0 (summaryTotalSize s)
  ]
