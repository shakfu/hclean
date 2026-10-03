-- | Named pattern sets and the rules for turning options into patterns.
module HClean.Preset
  ( presetNames
  , isPresetName
  , lookupPreset
  , expandPresets
  , defaultPatterns
  , protectedNames
  , resolvePatterns
  ) where

import Data.Char (toLower)
import Data.List (nub)
import Data.Maybe (fromMaybe, isJust)

import HClean.Types (Options (..))

-- | Every preset accepted on the command line or in a config file.
presetNames :: [String]
presetNames = ["common", "python", "node", "rust", "java", "c", "go", "all"]

-- | Is this a known preset? Names are matched without regard to case.
isPresetName :: String -> Bool
isPresetName = isJust . lookupPreset

-- | Patterns belonging to a preset, or 'Nothing' for an unknown name.
--
-- Names are matched without regard to case, so @node@ and @NODE@ are the same
-- preset.
lookupPreset :: String -> Maybe [String]
lookupPreset = byName . map toLower

byName :: String -> Maybe [String]
byName "common" =
  Just ["**/.DS_Store", "**/Thumbs.db", "**/*.swp", "**/*.swo"]
byName "python" =
  Just [ "**/__pycache__", "**/.coverage", "**/.mypy_cache", "**/.pylint_cache"
       , "**/.pytest_cache", "**/.ruff_cache", "**/.rumdl_cache", "**/.pyscn"
       , "**/.ropeproject", "**/pip-log.txt"
       , "**/*.pyc", "**/*.pyo" ]
byName "node" =
  Just [ "**/node_modules", "**/.next", "**/.nuxt", "**/.cache", "**/dist"
       , "**/.parcel-cache", "**/.turbo", "**/.eslintcache", "**/coverage"
       , "**/.nyc_output" ]
byName "rust" = Just ["**/target"]
byName "java" =
  Just [ "**/*.class", "**/target", "**/.gradle", "**/build", "**/.settings"
       , "**/.classpath", "**/.project" ]
byName "c" =
  Just [ "**/*.o", "**/*.obj", "**/*.a", "**/*.lib", "**/*.so", "**/*.dylib"
       , "**/*.dll" ]
byName "go" = Just ["**/vendor"]
byName "all" =
  Just (expandPresets (filter (/= "all") presetNames))
byName _ = Nothing

-- | Concatenate the given presets, ignoring unknown names.
expandPresets :: [String] -> [String]
expandPresets = nub . concatMap (fromMaybe [] . lookupPreset)

-- | Used when neither includes nor presets are given.
defaultPatterns :: [String]
defaultPatterns = expandPresets ["common", "python"]

-- | Directories never descended into or removed unless protection is disabled.
protectedNames :: [String]
protectedNames = [".git", ".hg", ".svn", ".config", ".ssh", ".gnupg"]

-- | The patterns a scan should use: explicit includes win, presets are always
-- added to them, and the defaults apply only when nothing else was requested.
resolvePatterns :: Options -> [String]
resolvePatterns o
  | not (null (optIncludes o)) = optIncludes o ++ expandPresets (optPresets o)
  | null (optPresets o)        = defaultPatterns
  | otherwise                  = expandPresets (optPresets o)
