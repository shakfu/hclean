-- | Removing matched paths.
module HClean.Delete
  ( removeTargets
  , removePath
  ) where

import System.Directory (doesDirectoryExist, removeFile, removePathForcibly)

import HClean.Types (Target (..))

-- | Remove every target, directories included.
removeTargets :: [Target] -> IO ()
removeTargets = mapM_ (removePath . targetPath)

-- | Remove a single path, recursively if it is a directory.
removePath :: FilePath -> IO ()
removePath p = do
  isDir <- doesDirectoryExist p
  if isDir then removePathForcibly p else removeFile p
