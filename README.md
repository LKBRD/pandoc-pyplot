# pandoc-pyplot

[![Hackage version](https://img.shields.io/hackage/v/pandoc-pyplot.svg)](http://hackage.haskell.org/package/pandoc-pyplot) [![Stackage version](http://stackage.org/package/pandoc-pyplot/badge/nightly)](http://stackage.org/nightly/package/pandoc-pyplot) [![Build status](https://ci.appveyor.com/api/projects/status/qbmq9cyks5jup48e?svg=true)](https://ci.appveyor.com/project/LaurentRDC/pandoc-pyplot)

## A Pandoc filter for generating figures with Matplotlib from code directly in documents

Inspired by [sphinx](https://sphinxdoc.org)'s `plot_directive`, `pandoc-pyplot` helps turn Python code present in your documents to embedded Matplotlib figures.

## Usage

The filter recognizes code blocks with the `plot_target` attribute present. It will run the script in the associated code block in a Python interpreter and capture the generated Matplotlib figure. This captured figure will be saved in the located specific by `plot_target`.

### Basic example

Here is a basic example using the scripting `matplotlib.pyplot` API:

```markdown
    ```{plot_target=my_figure.jpg}
    import matplotlib.pyplot as plt

    plt.figure()
    plt.plot([0,1,2,3,4], [1,2,3,4,5])
    plt.title('This is an example figure')
    ```
```

`pandoc-pyplot` will determine whether the `plot_target` is a relative or absolute path. In case of a relative path (like above), all paths will be considered relative to the current working directory.

We can control the format of the output file by changing the `plot_target` file extension. All formats supported by Matplotlib on your machine are available.

Putting the above in `input.md`, we can then generate the plot and embed it:

```bash
pandoc --filter pandoc-pyplot input.md --output output.html
```

or

```bash
pandoc --filter pandoc-pyplot input.md --output output.pdf
```

or any other output format you want. There are more examples in the source repository, in the `\examples` directory.

### Link to source code

In case of an output format that supports links (e.g. HTML), the embedded image generated by `pandoc-pyplot` will be a link to the source code which was used to generate the file. Therefore, other people can see what Python code was used to create your figures.

### Captions

You can also specify a caption for your image. This is done using the optional `plot_alt` parameter:

```markdown
    ```{plot_target=my_figure.jpg, plot_alt="This is a simple figure"}
    import matplotlib.pyplot as plt

    plt.figure()
    plt.plot([0,1,2,3,4], [1,2,3,4,5])
    plt.title('This is an example figure')
    ```
```

## Installation

### Binaries

Windows binaries are available on [GitHub](https://github.com/LaurentRDC/pandoc-pyplot/releases). Place the executable in a location that is in your PATH to be able to call it.

### From Hackage/Stackage

`pandoc-pyplot` is available on Hackage. Using the [`cabal-install`](https://www.haskell.org/cabal/) tool:

```bash
cabal update
cabal install pandoc-pyplot
```

Similarly, `pandoc-pyplot` is available on Stackage:

```bash
stack update
stack install pandoc-pyplot
```

### From source

Building from source can be done using [`stack`](https://docs.haskellstack.org/en/stable/README/) or [`cabal`](https://www.haskell.org/cabal/):

```bash
git clone github.com/LaurentRDC/pandoc-pyplot.git
cd pandoc-pylot
stack install # Alternatively, `cabal install`
```

## Running the filter

### Requirements

This filter only works with the Matplotlib plotting library. Therefore, you a Python interpreter and at least [Matplotlib](https://matplotlib.org/) installed. The python interpreter is expected to be discoverable using the name `"python"` (as opposed to `"python3"`, for example)

The filter program must be in your `PATH`. In case it is, you can use the filter with Pandoc as follows:

```bash
pandoc --filter pandoc-pyplot input.md output.html
```

Another example with PDF output:

```bash
pandoc --filter pandoc-pyplot input.md output.pdf
```

Python exceptions will be printed to screen in case of a problem.

`pandoc-pyplot` has a very limited command-line interface. Take a look at the help available using the `-h` or `--help` argument:

```bash
pandoc-pyplot --help
```

## Usage as a Haskell library

To include the functionality of `pandoc-pyplot` in a Haskell package, you can use the `makePlot :: Block -> IO Block` function (for single blocks) or `plotTransform :: Pandoc -> IO Pandoc` function (for entire documents).

### Usage with Hakyll

This filter was originally designed to be used with [Hakyll](https://jaspervdj.be/hakyll/). In case you want to use the filter with your own Hakyll setup, you can use a transform function that works on entire documents:

```haskell
import Text.Pandoc.Filter.Pyplot (plotTransform)

import Hakyll

-- Unsafe compiler is required because of the interaction
-- in IO (i.e. running an external Python script).
makePlotPandocCompiler :: Compiler (Item String)
makePlotPandocCompiler =
  pandocCompilerWithTransformM
    defaultHakyllReaderOptions
    defaultHakyllWriterOptions
    (unsafeCompiler . plotTransform)
```

## Warning

Do not run this filter on unknown documents. There is nothing in `pandoc-pyplot` that can stop a Python script from performing evil actions. This is the reason this package is deemed __unsafe__ in the parlance of [Safe Haskell](https://ghc.haskell.org/trac/ghc/wiki/SafeHaskell).

## Aknowledgements

This package is inspired from [`pandoc-include-code`](https://github.com/owickstrom/pandoc-include-code).
