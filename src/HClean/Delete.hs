-- | Removing matched paths.
module HClean.Delete
  ( Failure(..)
  , removeTargets
  , removePath
  ) where

import Control.Exception (IOException, try)
import System.Directory (doesDirectoryExist, removeFile, removePathForcibly)
import System.Posix.Files (fileSize, isDirectory, isSymbolicLink)

import HClean.Scan (directorySize, symlinkStatus)
import HClean.Types (Target (..))

-- | A target that could not be removed, and why.
data Failure = Failure
  { failureTarget :: Target
  , failureError  :: String
  }
  deriving (Eq, Show)

-- | Remove every target, directories included. A failure does not stop the
-- run. Returns the failures in target order and the bytes freed. @before@
-- runs ahead of each removal.
removeTargets :: (Target -> IO ()) -> [Target] -> IO ([Failure], Integer)
removeTargets before targets = do
  results <- mapM remove targets
  pure ([f | (Just f, _) <- results], sum (map snd results))
  where
    -- Freed bytes are the size before minus what a failed removal left, so
    -- 'removePathForcibly' keeps clearing read-only subdirectories.
    remove t = do
      before t
      size <- pathSize (targetPath t)
      err <- removePath (targetPath t)
      left <- maybe (pure 0) (const (pathSize (targetPath t))) err
      pure (Failure t <$> err, size - left)

-- | Remove a single path, recursively if it is a directory. Returns the error
-- message if it could not be removed.
removePath :: FilePath -> IO (Maybe String)
removePath p = either (Just . show) (const Nothing) <$> (try remove :: IO (Either IOException ()))
  where
    remove = do
      isDir <- doesDirectoryExist p
      if isDir then removePathForcibly p else removeFile p

-- | Apparent size of a path, not following symlinks; 0 if it is gone.
pathSize :: FilePath -> IO Integer
pathSize p = do
  mstatus <- symlinkStatus p
  case mstatus of
    Nothing -> pure 0
    Just s
      | isDirectory s && not (isSymbolicLink s) -> directorySize p
      | otherwise -> pure (fromIntegral (fileSize s))
