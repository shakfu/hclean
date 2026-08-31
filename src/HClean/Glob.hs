-- | A small glob matcher, deliberately dependency free.
module HClean.Glob
  ( globMatch
  , validGlob
  ) where

import Data.List (isPrefixOf)
import System.FilePath (splitDirectories, takeFileName)

-- | Match a glob against a relative path.
--
-- A pattern without a slash is matched against the basename only, which gives
-- the same convenient semantics as the Rust @globset@ crate used by rclean.
-- @**@ matches any number of path segments; within a segment @*@ matches any
-- run of characters and @?@ matches one.
globMatch :: String -> String -> Bool
globMatch pat path = any (matchSegments patternSegments) candidates
  where
    patternSegments = splitDirectories (map slash pat)
    candidates
      | '/' `notElem` pat = [[takeFileName path]]
      | otherwise         = [splitDirectories (map slash path)]

    slash c = if c == '\\' then '/' else c

    matchSegments [] [] = True
    matchSegments ("**" : ps) xs =
      matchSegments ps xs || case xs of
        []      -> False
        (_: ys) -> matchSegments ("**" : ps) ys
    matchSegments (p : ps) (x : xs) = matchSegment p x && matchSegments ps xs
    matchSegments _ _ = False

    matchSegment [] [] = True
    matchSegment ('*' : ps) xs = any (matchSegment ps) (suffixes xs)
    matchSegment ('?' : ps) (_ : xs) = matchSegment ps xs
    matchSegment ('[' : ps) (x : xs) = case parseClass ps of
      Nothing            -> False  -- unterminated class matches nothing
      Just (member, ps') -> member x && matchSegment ps' xs
    matchSegment (p : ps) (x : xs) = p == x && matchSegment ps xs
    matchSegment _ _ = False

    suffixes xs = xs : case xs of
      []      -> []
      (_: ys) -> suffixes ys

-- | One entry of a character class.
data ClassItem = Single Char | Range Char Char

-- | Parse a character class body (everything after the opening @[@) into a
-- predicate and the rest of the pattern.
--
-- Follows the usual shell conventions: a leading @!@ or @^@ negates the class,
-- @a-z@ is a range, and a @]@ in first position is a literal.
parseClass :: String -> Maybe (Char -> Bool, String)
parseClass body = case body of
  ('!' : rest) -> negate' <$> collect [] rest
  ('^' : rest) -> negate' <$> collect [] rest
  _            -> collect [] body
  where
    negate' (member, rest) = (not . member, rest)

    collect items (']' : rest)
      | not (null items) = Just (\c -> any (matches c) items, rest)
    collect items (lo : '-' : hi : rest)
      | hi /= ']' = collect (items ++ [Range lo hi]) rest
    collect items (c : rest) = collect (items ++ [Single c]) rest
    collect _ [] = Nothing

    matches c (Single x)     = c == x
    matches c (Range lo hi)  = lo <= c && c <= hi

-- | Reject patterns with an unterminated character class.
validGlob :: String -> Bool
validGlob = balanced
  where
    balanced []         = True
    balanced ('[' : xs) = "]" `isPrefixOf` xs || (']' `elem` xs && balanced xs)
    balanced (_ : xs)   = balanced xs
