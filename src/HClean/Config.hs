{-# LANGUAGE CPP #-}

-- | Reading and writing the @.hclean.toml@ configuration file.
--
-- Only the small subset of TOML that the file format actually uses is
-- understood: top level @key = value@ lines with string, boolean and string
-- array values, and @#@ comments. Reading stops at the first table header.
-- Unknown keys are ignored; a known key with a value of the wrong type is an
-- error.
--
-- Precedence: a list given on the command line (@--glob@, @--exclude@,
-- @--preset@) replaces the corresponding config list entirely, a boolean flag
-- given on the command line cannot be turned off by the file, and @--path@
-- overrides the file's @path@. A relative @path@ is resolved against the
-- file's directory, except in the global file, which belongs to no tree and
-- resolves against the working directory.
module HClean.Config
  ( ConfigSource(..)
  , resolveConfig
  , applyConfig
  , discoverConfig
  , writeDefaultConfig
  , configFileName
  , defaultConfigContents
  ) where

import Control.Applicative ((<|>))
import Control.Exception (IOException, finally, try)
import Control.Monad (filterM)
import Data.Maybe (listToMaybe)
import System.Directory (doesFileExist)
import System.Environment (lookupEnv)
import System.FilePath ((</>), dropTrailingPathSeparator, isAbsolute, normalise, takeDirectory)
import System.IO (hClose, hPutStr)
import System.IO.Error (catchIOError, isAlreadyExistsError)
import System.Posix.IO (OpenFileFlags (..), OpenMode (WriteOnly), defaultFileFlags, fdToHandle, openFd)

import HClean.Types (Options (..))
import HClean.Util (ancestorsBelowHome, trim)

-- | Where configuration should come from.
data ConfigSource
  = NoConfig            -- ^ Ignore configuration files entirely.
  | DiscoverConfig      -- ^ Search upwards, then fall back to the global file.
  | ConfigFile FilePath -- ^ Read this file.
  deriving (Eq, Show)

-- | A parsed value.
data Value = VString String | VBool Bool | VArray [String]

-- | Name looked for during discovery, and written by @--write-configfile@.
configFileName :: FilePath
configFileName = ".hclean.toml"

-- | Apply the selected configuration source to a set of options.
resolveConfig :: ConfigSource -> Options -> IO (Either String Options)
resolveConfig NoConfig o = pure (Right o)
resolveConfig (ConfigFile p) o = applyConfig p o
resolveConfig DiscoverConfig o = do
  local <- findUpward "."
  case local of
    Just file -> applyConfig file o
    Nothing -> maybe (pure (Right o)) (\file -> applyConfigIn Nothing file o) =<< globalConfig

-- | Merge a config file into @o@; values already set on the command line win.
-- A relative @path@ in the file is resolved against the file's directory.
applyConfig :: FilePath -> Options -> IO (Either String Options)
applyConfig path = applyConfigIn (Just (takeDirectory path)) path

-- | 'applyConfig', resolving a relative @path@ against @base@, or leaving it
-- relative to the working directory when @base@ is 'Nothing'.
applyConfigIn :: Maybe FilePath -> FilePath -> Options -> IO (Either String Options)
applyConfigIn base path o = do
  text <- try (readConfigFile path) :: IO (Either IOException String)
  pure $ case text of
    Left err -> Left (show err)
    Right t -> either (Left . ((path ++ ": ") ++)) Right (parseConfig t) >>= merge base path o

merge :: Maybe FilePath -> FilePath -> Options -> [(String, Value)] -> Either String Options
merge base path o entries = do
  root      <- str "path"
  patterns  <- arr "patterns"
  excludes  <- arr "exclude_patterns"
  presets   <- arr "presets"
  dryRun    <- flag "dry_run"
  assumeYes <- flag "skip_confirmation"
  stats     <- flag "stats_mode"
  symlinks  <- flag "include_symlinks"
  broken    <- flag "remove_broken_symlinks"
  artifacts <- flag "build_artifacts"
  pure o
    { optRoot           = optRoot o <|> (resolve <$> root)
    , optIncludes       = keep (optIncludes o) patterns
    , optExcludes       = keep (optExcludes o) excludes
    , optPresets        = keep (optPresets o) presets
    , optDryRun         = optDryRun o || dryRun
    , optAssumeYes      = optAssumeYes o || assumeYes
    , optStats          = optStats o || stats
    , optSymlinks       = optSymlinks o || symlinks
    , optBrokenSymlinks = optBrokenSymlinks o || broken
    , optArtifacts      = optArtifacts o || artifacts
    }
  where
    get key kind extract = case lookup key entries of
      Nothing -> Right Nothing
      Just v -> maybe (Left (path ++ ": " ++ key ++ " must be " ++ kind)) (Right . Just) (extract v)

    str key = get key "a string" (\v -> case v of VString x -> Just x; _ -> Nothing)
    arr key = get key "an array of strings" (\v -> case v of VArray x -> Just x; _ -> Nothing)
    flag key = (== Just True) <$> get key "a boolean" (\v -> case v of VBool x -> Just x; _ -> Nothing)

    keep [] (Just fromFile) = fromFile
    keep current _          = current

    resolve r = maybe r (\dir -> dropTrailingPathSeparator (normalise (dir </> r))) base

-- | Parse the top level @key = value@ lines, up to the first table header.
parseConfig :: String -> Either String [(String, Value)]
parseConfig = go (1 :: Int) . lines
  where
    go _ [] = Right []
    go n (raw : rest) = case trim raw of
      "" -> go (n + 1) rest
      ('#' : _) -> go (n + 1) rest
      ('[' : _) -> Right []
      line -> case break (== '=') line of
        (_, []) -> Left ("line " ++ show n ++ ": expected key = value")
        (key, _ : value) -> case parseValue value of
          Left err -> Left ("line " ++ show n ++ ": " ++ err)
          Right v -> ((trim key, v) :) <$> go (n + 1) rest

-- | Parse the text after @=@ on one line.
parseValue :: String -> Either String Value
parseValue s = case skip s of
  (q : rest) | isQuote q -> do
    (v, r) <- quoted q rest
    finished r
    Right (VString v)
  ('[' : rest) -> do
    (v, r) <- items [] rest
    finished r
    Right (VArray v)
  other -> case trim (takeWhile (/= '#') other) of
    "true"  -> Right (VBool True)
    "false" -> Right (VBool False)
    _       -> Left "expected a string, boolean or array"
  where
    skip = dropWhile (`elem` " \t")
    isQuote c = c == '"' || c == '\''

    finished r = case skip r of
      []      -> Right ()
      ('#' : _) -> Right ()
      _       -> Left "unexpected text after value"

    items acc r = case skip r of
      (']' : r') -> Right (reverse acc, r')
      (q : r') | isQuote q -> do
        (item, r'') <- quoted q r'
        case skip r'' of
          (',' : more) -> items (item : acc) more
          (']' : more) -> Right (reverse (item : acc), more)
          _            -> Left "expected , or ] in array"
      _ -> Left "array items must be strings"

-- | A string body after its opening quote, and the text after the closing
-- one. Basic (@"..."@) strings take escapes; literal (@'...'@) strings do not.
quoted :: Char -> String -> Either String (String, String)
quoted q = go []
  where
    go _ [] = Left "unterminated string"
    go acc (c : cs) | c == q = Right (reverse acc, cs)
    go acc ('\\' : c : cs) | q == '"' = case c of
      '"'  -> go ('"' : acc) cs
      '\\' -> go ('\\' : acc) cs
      'n'  -> go ('\n' : acc) cs
      't'  -> go ('\t' : acc) cs
      'r'  -> go ('\r' : acc) cs
      _    -> Left ("unsupported escape \\" ++ [c])
    go acc (c : cs) = go (c : acc) cs

-- | Look for 'configFileName' in @start@ and its ancestors below the home
-- directory, then in the global file (see 'globalConfig').
discoverConfig :: FilePath -> IO (Maybe FilePath)
discoverConfig start = maybe globalConfig (pure . Just) =<< findUpward start

-- | 'configFileName' in @start@ or its nearest ancestor below the home
-- directory; a file in @~@ or above is the global file's role.
findUpward :: FilePath -> IO (Maybe FilePath)
findUpward start = do
  candidates <- map (</> configFileName) <$> ancestorsBelowHome start
  listToMaybe <$> filterM doesFileExist candidates

-- | @hclean\/config.toml@ under @$XDG_CONFIG_HOME@, or under @~\/.config@
-- when that is unset or relative (the XDG spec ignores a relative value), if
-- it exists.
globalConfig :: IO (Maybe FilePath)
globalConfig = do
  xdg <- lookupEnv "XDG_CONFIG_HOME"
  home <- lookupEnv "HOME"
  let base = case xdg of
        Just d | isAbsolute d -> Just d
        _ -> (</> ".config") <$> home
  case (</> "hclean" </> "config.toml") <$> base of
    Nothing -> pure Nothing
    Just p -> do
      exists <- doesFileExist p
      pure (if exists then Just p else Nothing)

-- | Contents written by @--write-configfile@.
defaultConfigContents :: String
defaultConfigContents = unlines
  [ "path = \".\""
  , "patterns = [\"**/__pycache__\", \"**/*.pyc\"]"
  ]

-- | Write a starter config file. Returns 'False' without touching anything if
-- the path already exists, a dangling symlink included. The check and the
-- creation are one @O_EXCL@ open, so no other writer can slip in between.
writeDefaultConfig :: FilePath -> IO Bool
writeDefaultConfig path = (True <$ create) `catchIOError` \e ->
  if isAlreadyExistsError e then pure False else ioError e
  where
    create = do
      h <- fdToHandle =<< open
      hPutStr h defaultConfigContents `finally` hClose h
#if MIN_VERSION_unix(2,8,0)
    open = openFd path WriteOnly defaultFileFlags { exclusive = True, creat = Just 0o644 }
#else
    open = openFd path WriteOnly (Just 0o644) defaultFileFlags { exclusive = True }
#endif

-- | Read a config file completely, so the handle does not outlive the call.
readConfigFile :: FilePath -> IO String
readConfigFile path = do
  text <- readFile path
  length text `seq` pure text
