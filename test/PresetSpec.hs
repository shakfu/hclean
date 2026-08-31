module PresetSpec (tests) where

import Data.List (nub)

import HClean.Preset
import HClean.Types (Options (..), defaultOptions)
import Harness

tests :: TestGroup
tests = group "HClean.Preset"
  [ it "knows the documented presets" $
      assertEqual "names"
        ["common", "python", "node", "rust", "java", "c", "go", "all"]
        presetNames
  , it "looks presets up by name" $ do
      assertBool "python" (fmap (elem "**/__pycache__") (lookupPreset "python") == Just True)
      assertBool "rust" (lookupPreset "rust" == Just ["**/target"])
      assertEqual "unknown" Nothing (lookupPreset "nope")
  , it "ignores preset name case" $ do
      assertEqual "upper" (lookupPreset "node") (lookupPreset "NODE")
      assertEqual "mixed" (lookupPreset "python") (lookupPreset "Python")
  , it "expands and de-duplicates presets" $ do
      let expanded = expandPresets ["common", "python"]
      assertEqual "no duplicates" (nub expanded) expanded
      assertBool "from common" ("**/.DS_Store" `elem` expanded)
      assertBool "from python" ("**/*.pyc" `elem` expanded)
  , it "includes every other preset in 'all'" $ do
      let everything = expandPresets ["all"]
      assertBool "node" ("**/node_modules" `elem` everything)
      assertBool "rust" ("**/target" `elem` everything)
      assertBool "go" ("**/vendor" `elem` everything)
  , it "falls back to the default patterns" $
      assertEqual "defaults" defaultPatterns (resolvePatterns defaultOptions)
  , it "prefers explicit includes and adds presets to them" $ do
      let withGlobs = defaultOptions { optIncludes = ["**/*.log"] }
      assertEqual "includes only" ["**/*.log"] (resolvePatterns withGlobs)
      assertEqual "includes plus preset"
        ["**/*.log", "**/target"]
        (resolvePatterns withGlobs { optPresets = ["rust"] })
  , it "uses presets alone when no includes are given" $
      assertEqual "preset only"
        ["**/target"]
        (resolvePatterns defaultOptions { optPresets = ["rust"] })
  ]
