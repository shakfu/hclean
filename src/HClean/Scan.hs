{-# LANGUAGE MultiWayIf #-}

-- | Walking the file system and deciding what matches.
module HClean.Scan
  ( scan
  , scanWith
  , ScanHooks(..)
  , silentHooks
  , directorySize
  , isBuildArtifact
  , relativeTo
  , symlinkStatus
  ) where

import Control.Exception (catch)
import Control.Monad (filterM, forM)
import Data.List (intercalate, sort)
import Data.Maybe (fromMaybe, listToMaybe)
import Data.Time.Clock.POSIX (getPOSIXTime)
import System.Directory (doesFileExist, doesPathExist, listDirectory)
import System.FilePath ((</>), normalise, splitDirectories, takeDirectory, takeFileName)
import System.Posix.Files
  (FileStatus, fileSize, getSymbolicLinkStatus, isDirectory, isSymbolicLink, modificationTime)

import HClean.Glob (globMatch)
import HClean.Preset (protectedNames)
import HClean.Types (Options (..), Target (..))

-- | Directories that only count as build output when a matching project marker
-- sits next to them.
buildArtifactMarkers :: [(FilePath, [FilePath])]
buildArtifactMarkers =
  [ ("build", [ "CMakeLists.txt", "meson.build", "package.json", "build.gradle"
              , "build.gradle.kts", "pyproject.toml", "setup.py", "pubspec.yaml" ])
  , ("dist",          ["package.json", "pyproject.toml", "setup.py"])
  , ("target",        ["Cargo.toml", "pom.xml"])
  , (".next",         ["package.json"])
  , (".nuxt",         ["package.json"])
  , (".svelte-kit",   ["package.json"])
  , (".turbo",        ["package.json"])
  , (".parcel-cache", ["package.json"])
  , (".gradle",       ["build.gradle", "build.gradle.kts"])
  , ("zig-out",       ["build.zig"])
  , ("zig-cache",     ["build.zig"])
  , (".zig-cache",    ["build.zig"])
  , (".build",        ["Package.swift"])
  , ("_build",        ["mix.exs"])
  ]

-- | 'getSymbolicLinkStatus' that yields 'Nothing' instead of throwing.
symlinkStatus :: FilePath -> IO (Maybe FileStatus)
symlinkStatus p = (Just <$> getSymbolicLinkStatus p) `catchIO` const (pure Nothing)

catchIO :: IO a -> (IOError -> IO a) -> IO a
catchIO = catch

-- | Path of @p@ relative to @base@, using forward slashes.
relativeTo :: FilePath -> FilePath -> FilePath
relativeTo base p =
  intercalate "/" (drop (length (segments base)) (segments p))
  where segments = splitDirectories . normalise

-- | Is the entry at least @n@ seconds old? 'Nothing' accepts everything.
isOlderThan :: Maybe Integer -> FileStatus -> IO Bool
isOlderThan Nothing _ = pure True
isOlderThan (Just n) s = do
  now <- round <$> getPOSIXTime
  let modified = round (realToFrac (modificationTime s) :: Double)
  pure (now - modified >= n)

-- | Whether @path@ (named @name@) is build output of a git-tracked project.
isBuildArtifact :: FilePath -> FilePath -> IO Bool
isBuildArtifact path name = do
  let parent = takeDirectory path
      markers = fromMaybe [] (lookup name buildArtifactMarkers)
  inGitRepo <- doesPathExist (parent </> ".git")
  if not inGitRepo
    then pure False
    else not . null <$> filterM (doesFileExist . (parent </>)) markers

-- | Callbacks a front end can use to report progress while scanning.
data ScanHooks = ScanHooks
  { onVisit :: FilePath -> IO ()  -- ^ Runs for every entry examined.
  , onMatch :: Target -> IO ()    -- ^ Runs for every match, as it is found.
  }

-- | Hooks that do nothing.
silentHooks :: ScanHooks
silentHooks = ScanHooks (const (pure ())) (const (pure ()))

-- | Recursively collect everything under @base@ that the options select.
--
-- Matching directories are reported without descending into them, and excluded
-- or protected entries prune the walk. Symlinked directories are never
-- followed, so symlink loops cannot make the walk diverge.
scan :: Options -> FilePath -> [String] -> IO [Target]
scan = scanWith silentHooks

-- | 'scan', reporting each visited entry and each match to the given hooks.
scanWith :: ScanHooks -> Options -> FilePath -> [String] -> IO [Target]
scanWith hooks o base patterns = walk base
  where
    found t = onMatch hooks t >> pure [t]

    excluded p = any (`globMatch` relativeTo base p) (optExcludes o)
    protected p = not (optNoProtect o) && takeFileName p `elem` protectedNames

    walk dir = do
      entries <- listDirectory dir `catchIO` const (pure [])
      concat <$> forM (sort entries) (visit dir)

    visit dir name = do
      let path = dir </> name
          rel = relativeTo base path
      onVisit hooks path
      mstatus <- symlinkStatus path
      case mstatus of
        Nothing -> pure []
        Just s
          | excluded path || protected path -> pure []
          | otherwise -> do
              let link = isSymbolicLink s
                  isDir = isDirectory s
              artifact <- if optArtifacts o && isDir then isBuildArtifact path name else pure False
              old <- isOlderThan (optOlderThan o) s
              let matched = old && (artifact || any (`globMatch` rel) patterns)
              intact <- if link then doesPathExist path else pure True
              if | link && not (optSymlinks o) && not (optBrokenSymlinks o) ->
                     pure []
                 | link && optBrokenSymlinks o && not intact ->
                     found (Target path False "broken-symlink" (fromIntegral (fileSize s)))
                 | matched && (not link || optSymlinks o) ->
                     found (Target path isDir (reason artifact rel) (if isDir then 0 else fromIntegral (fileSize s)))
                 | isDir && not link ->
                     walk path
                 | otherwise ->
                     pure []

    reason True _ = "build-artifact"
    reason False rel =
      fromMaybe "unknown" (listToMaybe [p | p <- patterns, globMatch p rel])

-- | Total size in bytes of a directory tree, not following symlinks.
directorySize :: FilePath -> IO Integer
directorySize path = do
  entries <- listDirectory path `catchIO` const (pure [])
  sum <$> forM entries (\name -> do
    let child = path </> name
    mstatus <- symlinkStatus child
    case mstatus of
      Nothing -> pure 0
      Just s
        | isDirectory s && not (isSymbolicLink s) -> directorySize child
        | otherwise -> pure (fromIntegral (fileSize s)))
