-- | A small glob matcher, deliberately dependency free.
module HClean.Glob
  ( globMatch
  , validGlob
  ) where

import Data.Maybe (isJust)
import System.FilePath (splitDirectories, takeFileName)

-- | One path segment of a parsed pattern.
data Segment = Globstar | Atoms [Atom]

-- | One unit of a segment pattern.
data Atom = Literal Char | AnyChar | Star | Class (Char -> Bool)

-- | Match a glob against a relative path.
--
-- A pattern without a slash is matched against the basename only, which gives
-- the same convenient semantics as the Rust @globset@ crate used by rclean.
-- @**@ matches any number of path segments; within a segment @*@ matches any
-- run of characters and @?@ matches one. An invalid pattern matches nothing.
globMatch :: String -> String -> Bool
globMatch pat path = maybe False (`matchSegments` candidate) (parseGlob pat)
  where
    candidate
      | '/' `notElem` map slash pat = [takeFileName path]
      | otherwise                   = splitDirectories (map slash path)

-- | Reject patterns with an unterminated or empty character class.
validGlob :: String -> Bool
validGlob = isJust . parseGlob

slash :: Char -> Char
slash c = if c == '\\' then '/' else c

parseGlob :: String -> Maybe [Segment]
parseGlob = mapM segment . splitDirectories . map slash
  where
    segment "**" = Just Globstar
    segment s    = Atoms <$> atoms s

    atoms [] = Just []
    atoms ('*' : xs) = (Star :) <$> atoms (dropWhile (== '*') xs)
    atoms ('?' : xs) = (AnyChar :) <$> atoms xs
    atoms ('[' : xs) = do
      (member, rest) <- parseClass xs
      (Class member :) <$> atoms rest
    atoms (c : xs) = (Literal c :) <$> atoms xs

matchSegments :: [Segment] -> [String] -> Bool
matchSegments = backtrack isGlobstar step
  where
    isGlobstar Globstar = True
    isGlobstar _        = False
    step (Atoms as) x = backtrack isStar matchAtom as x
    step Globstar _   = False

    isStar Star = True
    isStar _    = False
    matchAtom (Literal c) x = c == x
    matchAtom AnyChar _     = True
    matchAtom (Class m) x   = m x
    matchAtom Star _        = False

-- | Wildcard matching in which every non-wildcard item consumes exactly one
-- subject item. Only the most recent wildcard is retried, which is
-- sufficient here and keeps the cost at O(pattern * subject).
backtrack :: (p -> Bool) -> (p -> x -> Bool) -> [p] -> [x] -> Bool
backtrack isWild step = go Nothing
  where
    go _ (p : ps) xs
      | isWild p = go (Just (ps, xs)) ps xs
    go _ [] [] = True
    go restart (p : ps) (x : xs)
      | step p x = go restart ps xs
    go (Just (rps, _ : rxs)) _ _ = go (Just (rps, rxs)) rps rxs
    go _ _ _ = False

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
