-- | Turning a set of targets into text or JSON.
module HClean.Report
  ( Summary(..)
  , PatternStat(..)
  , summarize
  , renderText
  , renderJson
  , formatSize
  ) where

import Control.Monad (forM)
import Data.List (intercalate, nub)
import HClean.Scan (directorySize)
import HClean.Types (Target (..))

-- | Aggregate figures for one pattern.
data PatternStat = PatternStat
  { statPattern :: String
  , statCount   :: Int
  , statSize    :: Integer
  }
  deriving (Eq, Show)

-- | Targets with their sizes resolved, plus the totals derived from them.
data Summary = Summary
  { summaryTargets   :: [Target]
  , summaryTotalSize :: Integer
  , summaryStats     :: [PatternStat]
  }

-- | Measure directory targets and compute the totals.
summarize :: [Target] -> IO Summary
summarize targets = do
  sized <- forM targets $ \t ->
    if targetIsDir t
      then (\n -> t { targetSize = n }) <$> directorySize (targetPath t)
      else pure t
  pure Summary
    { summaryTargets = sized
    , summaryTotalSize = sum (map targetSize sized)
    , summaryStats =
        [ PatternStat p (length matching) (sum (map targetSize matching))
        | p <- nub (map targetPattern sized)
        , let matching = filter ((== p) . targetPattern) sized
        ]
    }

-- | Human readable listing; @showStats@ appends the per-pattern breakdown.
renderText :: Bool -> Summary -> String
renderText showStats s = unlines $
  map (("Matched: " ++) . targetPath) (summaryTargets s)
    ++ [ "  " ++ statPattern st ++ ": " ++ show (statCount st)
           ++ " item(s), " ++ formatSize (statSize st)
       | showStats, st <- summaryStats s
       ]

-- | Machine readable report. @dryRun@ is echoed back in the summary object.
renderJson :: Bool -> Summary -> String
renderJson dryRun s = object
  [ ("matches", array (map match (summaryTargets s)))
  , ("summary", object
      [ ("total_count", show (length (summaryTargets s)))
      , ("total_size", show (summaryTotalSize s))
      , ("total_size_human", jsonString (formatSize (summaryTotalSize s)))
      , ("dry_run", if dryRun then "true" else "false")
      ])
  , ("stats", array (map stat (summaryStats s)))
  , ("failures", array [])
  ]
  where
    match t = object
      [ ("path", jsonString (targetPath t))
      , ("size", show (targetSize t))
      , ("pattern", jsonString (targetPattern t))
      ]
    stat st = object
      [ ("pattern", jsonString (statPattern st))
      , ("count", show (statCount st))
      , ("size", show (statSize st))
      , ("size_human", jsonString (formatSize (statSize st)))
      ]
    object fields = "{" ++ intercalate "," [jsonString k ++ ":" ++ v | (k, v) <- fields] ++ "}"
    array items = "[" ++ intercalate "," items ++ "]"

-- | Quote a string as JSON. Control characters are escaped as @\uXXXX@;
-- other characters are emitted as-is, which is valid in a UTF-8 document.
jsonString :: String -> String
jsonString s = '"' : concatMap escape s ++ "\""
  where
    escape '"'  = "\\\""
    escape '\\' = "\\\\"
    escape '\n' = "\\n"
    escape '\r' = "\\r"
    escape '\t' = "\\t"
    escape '\b' = "\\b"
    escape '\f' = "\\f"
    escape c
      | c < ' ' || c == '\DEL' = "\\u" ++ pad (showHex (fromEnum c))
      | otherwise = [c]

    pad h = replicate (4 - length h) '0' ++ h

    showHex 0 = "0"
    showHex n = go n ""
      where
        go 0 acc = acc
        go m acc = go (m `div` 16) (digit (m `mod` 16) : acc)
        digit d = (['0' .. '9'] ++ ['a' .. 'f']) !! d

-- | Render a byte count using binary units.
formatSize :: Integer -> String
formatSize n
  | n >= tib = twoDecimals (fromIntegral n / fromIntegral tib) ++ " TiB"
  | n >= gib = twoDecimals (fromIntegral n / fromIntegral gib) ++ " GiB"
  | n >= mib = twoDecimals (fromIntegral n / fromIntegral mib) ++ " MiB"
  | n >= kib = twoDecimals (fromIntegral n / fromIntegral kib) ++ " KiB"
  | otherwise = show n ++ " B"
  where
    kib = 1024 :: Integer
    mib = kib * 1024
    gib = mib * 1024
    tib = gib * 1024

twoDecimals :: Double -> String
twoDecimals x =
  let rendered = show (fromIntegral (round (x * 100) :: Integer) / 100 :: Double)
      (whole, rest) = span (/= '.') rendered
  in whole ++ "." ++ take 2 (drop 1 rest ++ "00")
