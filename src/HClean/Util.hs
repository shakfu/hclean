-- | Small helpers shared by the other modules.
module HClean.Util
  ( trim
  , parseDuration
  , ancestorsBelowHome
  ) where

import Data.Char (isDigit, isSpace)
import System.Directory (canonicalizePath, makeAbsolute)
import System.Environment (lookupEnv)
import System.FilePath (normalise, takeDirectory)

-- | Strip leading and trailing whitespace.
trim :: String -> String
trim = dropWhile isSpace . reverse . dropWhile isSpace . reverse

-- | Parse a duration such as @30m@ or @2w@ into a number of seconds.
--
-- >>> parseDuration "30m"
-- Right 1800
parseDuration :: String -> Either String Integer
parseDuration raw = case span isDigit (trim raw) of
  (digits, [unit]) | not (null digits) ->
    let n = read digits
    in case unit of
         's' -> Right n
         'm' -> Right (n * 60)
         'h' -> Right (n * 3600)
         'd' -> Right (n * 86400)
         'w' -> Right (n * 604800)
         _   -> Left "duration unit must be s, m, h, d, or w"
  _ -> Left "duration must be a number followed by a unit"

-- | @start@ made absolute, then its ancestors, nearest first. The list stops
-- below the home directory, leaving out @~@ and everything above it, so a
-- file there cannot claim every directory under @~@. A start outside @~@
-- runs to the root.
ancestorsBelowHome :: FilePath -> IO [FilePath]
ancestorsBelowHome start = do
  home <- traverse canonicalizePath =<< lookupEnv "HOME"
  let atHome dir = maybe (pure False) (\h -> (== h) <$> canonicalizePath dir) home
      climb dir = do
        stop <- atHome dir
        let parent = takeDirectory dir
        if stop then pure []
          else if parent == dir then pure [dir]
          else (dir :) <$> climb parent
  climb . normalise =<< makeAbsolute start
