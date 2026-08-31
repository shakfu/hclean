module GlobSpec (tests) where

import HClean.Glob (globMatch, validGlob)
import Harness

tests :: TestGroup
tests = group "HClean.Glob"
  [ it "matches a slashless pattern against the basename" $ do
      assertBool "*.pyc" (globMatch "*.pyc" "a/b/c.pyc")
      assertBool ".DS_Store" (globMatch ".DS_Store" "deep/nested/.DS_Store")
  , it "anchors patterns containing a slash to the whole path" $ do
      assertBool "src/*.hs" (globMatch "src/*.hs" "src/Main.hs")
      assertBool "not nested" (not (globMatch "src/*.hs" "src/a/Main.hs"))
      assertBool "not elsewhere" (not (globMatch "src/*.hs" "lib/src/Main.hs"))
  , it "lets ** span any number of segments" $ do
      assertBool "top level" (globMatch "**/__pycache__" "__pycache__")
      assertBool "one level" (globMatch "**/__pycache__" "a/__pycache__")
      assertBool "many levels" (globMatch "**/__pycache__" "a/b/c/__pycache__")
      assertBool "suffix must match" (not (globMatch "**/__pycache__" "a/__pycache__/b"))
  , it "matches ? against exactly one character" $ do
      assertBool "one" (globMatch "a?c.txt" "a-c.txt")
      assertBool "not zero" (not (globMatch "a?c.txt" "ac.txt"))
      assertBool "not two" (not (globMatch "a?c.txt" "a--c.txt"))
  , it "treats backslashes as separators" $
      assertBool "windows style" (globMatch "**\\target" "a/target")
  , it "matches character classes" $ do
      assertBool "member" (globMatch "[abc].txt" "b.txt")
      assertBool "non-member" (not (globMatch "[abc].txt" "d.txt"))
      assertBool "range" (globMatch "file[0-9].log" "file7.log")
      assertBool "outside range" (not (globMatch "file[0-9].log" "filex.log"))
      assertBool "negated" (globMatch "[!abc].txt" "d.txt")
      assertBool "negated member" (not (globMatch "[!abc].txt" "a.txt"))
      assertBool "caret negation" (not (globMatch "[^abc].txt" "a.txt"))
      assertBool "literal ] first" (globMatch "[]a].txt" "].txt")
      assertBool "class needs one character" (not (globMatch "[abc]" ""))
  , it "combines classes with other wildcards" $ do
      assertBool "star and class" (globMatch "**/*.[ch]" "src/main.c")
      assertBool "wrong extension" (not (globMatch "**/*.[ch]" "src/main.rs"))
  , it "accepts balanced patterns and rejects unterminated classes" $ do
      assertBool "closed" (validGlob "[abc].txt")
      assertBool "empty class" (validGlob "[]]")
      assertBool "no class" (validGlob "**/*.log")
      assertBool "unterminated" (not (validGlob "[abc.txt"))
  ]
