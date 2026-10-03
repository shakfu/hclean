-- | Core data types shared by the library and its front ends.
module HClean.Types
  ( Options(..)
  , defaultOptions
  , scanRoot
  , OutputFormat(..)
  , Target(..)
  ) where

import Data.Maybe (fromMaybe)

-- | How results are rendered.
data OutputFormat = TextFormat | JsonFormat
  deriving (Eq, Show)

-- | Everything that influences which paths are matched and how they are
-- reported. Front ends fill this in from arguments and\/or a config file.
data Options = Options
  { optRoot           :: Maybe FilePath -- ^ Directory to scan; 'Nothing' means @.@.
  , optIncludes       :: [String]   -- ^ Explicit include globs.
  , optExcludes       :: [String]   -- ^ Globs that prune the walk.
  , optPresets        :: [String]   -- ^ Named preset pattern sets.
  , optDryRun         :: Bool       -- ^ Report matches without deleting.
  , optAssumeYes      :: Bool       -- ^ Skip the confirmation prompt.
  , optStats          :: Bool       -- ^ Include per-pattern statistics.
  , optOlderThan      :: Maybe Integer -- ^ Only match entries at least this many seconds old.
  , optFormat         :: OutputFormat
  , optNoProtect      :: Bool       -- ^ Disable the protected-directory list.
  , optSymlinks       :: Bool       -- ^ Remove matching symlinks.
  , optBrokenSymlinks :: Bool       -- ^ Remove dangling symlinks.
  , optArtifacts      :: Bool       -- ^ Match build output directories.
  , optQuiet          :: Bool       -- ^ Suppress the text listing.
  }
  deriving (Eq, Show)

-- | Scan the current directory with the built-in default patterns.
defaultOptions :: Options
defaultOptions = Options
  { optRoot           = Nothing
  , optIncludes       = []
  , optExcludes       = []
  , optPresets        = []
  , optDryRun         = False
  , optAssumeYes      = False
  , optStats          = False
  , optOlderThan      = Nothing
  , optFormat         = TextFormat
  , optNoProtect      = False
  , optSymlinks       = False
  , optBrokenSymlinks = False
  , optArtifacts      = False
  , optQuiet          = False
  }

-- | The directory to scan.
scanRoot :: Options -> FilePath
scanRoot = fromMaybe "." . optRoot

-- | A path selected for removal, together with why it matched.
data Target = Target
  { targetPath      :: FilePath
  , targetIsDir     :: Bool
  , targetPattern   :: String   -- ^ Matching glob, @build-artifact@ or @broken-symlink@.
  , targetSize      :: Integer  -- ^ Size in bytes; 0 for directories until summarised.
  }
  deriving (Eq, Show)
