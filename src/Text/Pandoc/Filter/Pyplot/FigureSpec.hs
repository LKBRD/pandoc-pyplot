{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Text.Pandoc.Filter.Pyplot.FigureSpec
Copyright   : (c) Laurent P René de Cotret, 2019
License     : MIT
Maintainer  : laurent.decotret@outlook.com
Stability   : internal
Portability : portable

This module defines types and functions that help
with keeping track of figure specifications
-}
module Text.Pandoc.Filter.Pyplot.FigureSpec
    ( FigureSpec(..)
    , SaveFormat(..)
    , saveFormatFromString
    , toImage
    , sourceCodePath
    , figurePath
    , addPlotCapture
    , parseFigureSpec
    -- for testing purposes
    , extension
    ) where

import           Control.Monad                (join)

import           Data.Default.Class           (def)
import           Data.Hashable                (hash)
import           Data.List                    (intersperse)
import qualified Data.Map.Strict              as Map
import           Data.Maybe                   (fromMaybe)
import           Data.Monoid                  ((<>))
import qualified Data.Text                    as T
import qualified Data.Text.IO                 as T
import           Data.Version                 (showVersion)

import           Paths_pandoc_pyplot          (version)

import           System.FilePath              (FilePath, addExtension,
                                               replaceExtension, (</>), makeValid)

import           Text.Pandoc.Definition       
import           Text.Pandoc.Builder          (imageWith, link, para, fromList, toList)

import           Text.Pandoc.Class            (runPure)
import           Text.Pandoc.Extensions       (extensionsFromList, Extension(..))
import           Text.Pandoc.Options          (ReaderOptions(..))
import           Text.Pandoc.Readers          (readMarkdown)

import Text.Pandoc.Filter.Pyplot.Types
import Text.Pandoc.Filter.Pyplot.Configuration


readerOptions :: ReaderOptions
readerOptions = def 
    {readerExtensions = 
        extensionsFromList 
            [ Ext_tex_math_dollars
            , Ext_superscript 
            , Ext_subscript
            ] 
    }

-- | Read a figure caption in Markdown format. LaTeX math @$...$@ is supported,
-- as are Markdown subscripts and superscripts.
captionReader :: String -> Maybe [Inline]
captionReader t = either (const Nothing) (Just . extractFromBlocks) $ runPure $ readMarkdown' (T.pack t)
    where
        readMarkdown' = readMarkdown readerOptions

        extractFromBlocks (Pandoc _ blocks) = mconcat $ extractInlines <$> blocks

        extractInlines (Plain inlines) = inlines
        extractInlines (Para inlines) = inlines
        extractInlines (LineBlock multiinlines) = join multiinlines
        extractInlines _ = []


-- | Code block class that will trigger the filter
filterClass :: String
filterClass = "pyplot"


-- | Flexible boolean parsing
readBool :: String -> Bool
readBool s | s `elem` ["True",  "true",  "'True'",  "'true'",  "1"] = True
           | s `elem` ["False", "false", "'False'", "'false'", "0"] = False
           | otherwise = error $ mconcat ["Could not parse '", s, "' into a boolean. Please use 'True' or 'False'"] 

-- | Determine inclusion specifications from Block attributes.
-- Note that the @".pyplot"@ class is required, but all other parameters are optional
parseFigureSpec :: Configuration -> Block -> IO (Maybe FigureSpec)
parseFigureSpec config (CodeBlock (id', cls, attrs) content)
    | filterClass `elem` cls = Just <$> figureSpec
    | otherwise = return Nothing
  where
    attrs'        = Map.fromList attrs
    filteredAttrs = filter (\(k, _) -> k `notElem` inclusionKeys) attrs
    includePath   = Map.lookup includePathKey attrs'

    figureSpec :: IO FigureSpec
    figureSpec = do
        includeScript <- fromMaybe (return $ defaultIncludeScript config) $ T.readFile <$> includePath
        let header      = "# Generated by pandoc-pyplot " <> ((T.pack . showVersion) version)
            fullScript  = mconcat $ intersperse "\n" [header, includeScript, T.pack content]
            caption'    = Map.findWithDefault mempty captionKey attrs'
            label'      = Map.lookup labelKey attrs'
            format      = fromMaybe (defaultSaveFormat config) $ join $ saveFormatFromString <$> Map.lookup saveFormatKey attrs'
            dir         = makeValid $ Map.findWithDefault (defaultDirectory config) directoryKey attrs'
            dpi'        = fromMaybe (defaultDPI config) $ read <$> Map.lookup dpiKey attrs'
            withLinks'  = fromMaybe (defaultWithLinks config) $ readBool <$> Map.lookup withLinksKey attrs'
            blockAttrs' = (fromMaybe id' label', filter (/= filterClass) cls, filteredAttrs)
        return $ FigureSpec caption' withLinks' fullScript format dir dpi' label' blockAttrs'
    
parseFigureSpec _ _ = return Nothing

-- | Convert a FigureSpec to a Pandoc block component
toImage :: FigureSpec -> Block
toImage spec = head . toList $ para $ imageWith attrs' target' "fig:" caption'
    -- To render images as figures with captions, the target title
    -- must be "fig:"
    -- Janky? yes
    where
        attrs'       = blockAttrs spec
        target'      = figurePath spec
        withLinks'   = withLinks spec
        srcLink      = link (replaceExtension target' ".txt") mempty "Source code" 
        hiresLink    = link (hiresFigurePath spec) mempty "high res."
        captionText  = fromList $ fromMaybe mempty (captionReader $ caption spec)
        captionLinks = mconcat [" (", srcLink, ", ", hiresLink, ")"]
        caption'     = if withLinks' then captionText <> captionLinks else captionText

-- | Determine the path a figure should have.
figurePath :: FigureSpec -> FilePath
figurePath spec = directory spec </> stem spec
  where
    stem = flip addExtension ext . show . hash
    ext  = extension . saveFormat $ spec

-- | Determine the path to the source code that generated the figure.
sourceCodePath :: FigureSpec -> FilePath
sourceCodePath = flip replaceExtension ".txt" . figurePath

-- | The path to the high-resolution figure.
hiresFigurePath :: FigureSpec -> FilePath
hiresFigurePath spec = flip replaceExtension (".hires" <> ext) . figurePath $ spec
  where
    ext = extension . saveFormat $ spec

-- | Modify a Python plotting script to save the figure to a filename.
-- An additional file will also be captured.
addPlotCapture :: FigureSpec   -- ^ Path where to save the figure
               -> PythonScript -- ^ Code block with added capture
addPlotCapture spec =
    mconcat
        [ script spec
        , "\nimport matplotlib.pyplot as plt" -- Just in case
        , plotCapture (figurePath spec) (dpi spec)
        , plotCapture (hiresFigurePath spec) (minimum [200, 2 * dpi spec])
        ]
  where
    plotCapture fname' dpi' =
        mconcat
            [ "\nplt.savefig("
            , T.pack $ show fname' -- show is required for quotes
            , ", dpi="
            , T.pack $ show dpi'
            , ")"
            ]
