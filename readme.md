# fakeneko

this is a dumb n-depth markov chain based "model" trainer, runner, server,
merger, dumbifier.

## features

- train models based on multiple text (or even binary) files with customizable
  depth (even 0!)
- run those models
- serve those models over an openai compatible api _**(todo)**_
- merge multiple trained models (only if trained on same depth)
- decrease depth of models (useful when merging multi-depth models)

### stuff you can use this for

- generate gibberish that sounds like an actual language to those who dont speak
  that language. (if you train it with the correct depth and data)
- generate interesting stuff

### stuff you cannot use this for

- taking over the world

## important things to keep in mind

- more depth != more better. this is only valid if you have enough data. i feel
  like depth of 3-6 is great for a million lines of text. otherwise more depth
  will just make it spit out stuff it already saw in the training data files
  (most of the time)
- this is not a chatbot, just fancy autocomplete. it completely disregards
  whatever user says (most of the time)

## usage

### compiling

```bash
zig build -Doptimize=ReleaseFast
```

or use whatever optimization you want, even `ReleaseSmall` works.

use binaries if i choose to add them later and you want to do it that way.

## known issues

- when a non-trained model is run, it returns a null array of length
  `max_length`. if you face this error, this is your fault
