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
    -- for testing purposes
    , extension
    ) where

import           Control.Monad                (join)

import           Data.Hashable                (Hashable, hash, hashWithSalt)
import           Data.Maybe                   (fromMaybe)
import           Data.Monoid                  ((<>))
import qualified Data.Text                    as T

import           System.FilePath              (FilePath, addExtension,
                                               replaceExtension, (</>))

import           Text.Pandoc.Definition       
import           Text.Pandoc.Builder          (imageWith, link, para, fromList, toList)

import           Text.Pandoc.Class            (runPure)
import           Text.Pandoc.Extensions       (extensionsFromList, Extension(..))
import           Text.Pandoc.Options          (def, ReaderOptions(..))
import           Text.Pandoc.Readers          (readMarkdown)

import Text.Pandoc.Filter.Pyplot.Scripting

readerOptions :: ReaderOptions
readerOptions = def 
    {readerExtensions = 
        extensionsFromList 
            [ Ext_tex_math_dollars
            , Ext_superscript 
            , Ext_subscript
            ] 
    }

-- | Read a figure caption in Markdown format.
captionReader :: String -> Maybe [Inline]
captionReader t = either (const Nothing) (Just . extractFromBlocks) $ runPure $ readMarkdown' (T.pack t)
    where
        readMarkdown' = readMarkdown readerOptions

        extractFromBlocks (Pandoc _ blocks) = mconcat $ extractInlines <$> blocks

        extractInlines (Plain inlines) = inlines
        extractInlines (Para inlines) = inlines
        extractInlines (LineBlock multiinlines) = join multiinlines
        extractInlines _ = []

data SaveFormat
    = PNG
    | PDF
    | SVG
    | JPG
    | EPS
    deriving (Enum, Eq, Show)

-- | Parse an image save format string
saveFormatFromString :: String -> Maybe SaveFormat
saveFormatFromString s
    | s `elem` ["png", "PNG", ".png"] = Just PNG
    | s `elem` ["pdf", "PDF", ".pdf"] = Just PDF
    | s `elem` ["svg", "SVG", ".svg"] = Just SVG
    | s `elem` ["jpg", "jpeg", "JPG", "JPEG", ".jpg", ".jpeg"] = Just JPG
    | s `elem` ["eps", "EPS", ".eps"] = Just EPS
    | otherwise = Nothing

-- | Save format file extension
extension :: SaveFormat -> String
extension PNG = ".png"
extension PDF = ".pdf"
extension SVG = ".svg"
extension JPG = ".jpg"
extension EPS = ".eps"

-- | Datatype containing all parameters required
-- to run pandoc-pyplot
data FigureSpec = FigureSpec
    { caption    :: String -- ^ Figure caption.
    , script     :: PythonScript -- ^ Source code for the figure.
    , saveFormat :: SaveFormat -- ^ Save format of the figure
    , directory  :: FilePath -- ^ Directory where to save the file
    , dpi        :: Int -- ^ Dots-per-inch of figure
    , blockAttrs :: Attr -- ^ Attributes not related to @pandoc-pyplot@ will be propagated.
    }

instance Hashable FigureSpec where
    hashWithSalt salt spec =
        hashWithSalt salt (caption spec, script spec, directory spec, dpi spec, blockAttrs spec)

-- | Convert a FigureSpec to a Pandoc block component
toImage :: FigureSpec -> Block
toImage spec = head . toList $ para $ imageWith attrs' target' "fig:" caption'
    -- To render images as figures with captions, the target title
    -- must be "fig:"
    -- Janky? yes
    where
        attrs'       = blockAttrs spec
        target'      = figurePath spec
        srcLink      = link (replaceExtension target' ".txt") mempty "Source code" 
        hiresLink    = link (hiresFigurePath spec) mempty "high res."
        captionText  = fromList $ fromMaybe mempty (captionReader $ caption spec)
        captionLinks = mconcat [" (", srcLink, ", ", hiresLink, ")"]
        caption'     = captionText <> captionLinks

-- | Determine the path a figure should have.
figurePath :: FigureSpec -> FilePath
figurePath spec = (directory spec </> stem spec)
  where
    stem = flip addExtension ext . show . hash
    ext = extension . saveFormat $ spec

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
