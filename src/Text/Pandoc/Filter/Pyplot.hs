{-# LANGUAGE MultiWayIf        #-}
{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : $header$
Description : Pandoc filter to create Matplotlib/Plotly figures from code blocks
Copyright   : (c) Laurent P René de Cotret, 2019
License     : GNU GPL, version 2 or above
Maintainer  : laurent.decotret@outlook.com
Stability   : stable
Portability : portable

This module defines a Pandoc filter @makePlot@ and related functions
that can be used to walk over a Pandoc document and generate figures from
Python code blocks.

The syntax for code blocks is simple, Code blocks with the @.pyplot@ or @.plotly@
attribute will trigger the filter. The code block will be reworked into a Python
script and the output figure will be captured, along with a high-resolution version
of the figure and the source code used to generate the figure.

To trigger pandoc-pyplot, one of the following is __required__:

    * @.pyplot@: Trigger pandoc-pyplot, rendering via the Matplotlib library
    * @.plotly@: Trigger pandoc-pyplot, rendering via the Plotly library

Here are the possible attributes what pandoc-pyplot understands:

    * @directory=...@ : Directory where to save the figure.
    * @format=...@: Format of the generated figure. This can be an extension or an acronym, e.g. @format=png@.
    * @caption="..."@: Specify a plot caption (or alternate text). Captions support Markdown formatting and LaTeX math (@$...$@).
    * @dpi=...@: Specify a value for figure resolution, or dots-per-inch. Default is 80DPI. (Matplotlib only, ignored otherwise)
    * @include=...@: Path to a Python script to include before the code block. Ideal to avoid repetition over many figures.
    * @links=true|false@: Add links to source code and high-resolution version of this figure.
      This is @true@ by default, but you may wish to disable this for PDF output.

Custom configurations are possible via the @Configuration@ type and the filter
functions @plotTransformWithConfig@ and @makePlotWithConfig@.
-}
module Text.Pandoc.Filter.Pyplot (
    -- * Operating on single Pandoc blocks
      makePlot
    , makePlotWithConfig
    -- * Operating on whole Pandoc documents
    , plotTransform
    , plotTransformWithConfig
    -- * For configuration purposes
    , configuration
    , Configuration (..)
    , PythonScript
    , SaveFormat (..)
    -- * For testing and internal purposes only
    , PandocPyplotError(..)
    , makePlot'
    ) where

import           Control.Monad.Reader

import           Data.Default.Class                 (def)

import           Text.Pandoc.Definition
import           Text.Pandoc.Walk                   (walkM)

import           Text.Pandoc.Filter.Pyplot.Internal

-- | Main routine to include plots.
-- Code blocks containing the attributes @.pyplot@ or @.plotly@ are considered
-- Python plotting scripts. All other possible blocks are ignored.
makePlot' :: Block -> PyplotM (Either PandocPyplotError Block)
makePlot' block = do
    parsed <- parseFigureSpec block
    maybe
        (return $ Right block)
        (\s -> handleResult s <$> runScriptIfNecessary s)
        parsed
    where
        handleResult _ (ScriptChecksFailed msg) = Left  $ ScriptChecksFailedError msg
        handleResult _ (ScriptFailure code)     = Left  $ ScriptError code
        handleResult spec ScriptSuccess         = Right $ toImage spec

-- | Highest-level function that can be walked over a Pandoc tree.
-- All code blocks that have the @.pyplot@ / @.plotly@ class will be considered
-- figures.
makePlot :: Block -> IO Block
makePlot = makePlotWithConfig def

-- | like @makePlot@ with with a custom default values.
--
-- @since 2.1.0.0
makePlotWithConfig :: Configuration -> Block -> IO Block
makePlotWithConfig config block =
    runReaderT (makePlot' block >>= either (fail . show) return) config

-- | Walk over an entire Pandoc document, changing appropriate code blocks
-- into figures. Default configuration is used.
plotTransform :: Pandoc -> IO Pandoc
plotTransform = walkM makePlot

-- | Walk over an entire Pandoc document, changing appropriate code blocks
-- into figures. The default values are determined by a @Configuration@.
--
-- @since 2.1.0.0
plotTransformWithConfig :: Configuration -> Pandoc -> IO Pandoc
plotTransformWithConfig = walkM . makePlotWithConfig
