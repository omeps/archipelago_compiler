# Compiler for archipelago, the language made for CMIMC 2025 New Language round
## Features
- if/while statements
- nested control flow
- keywords for swapping
## basic usage
- Compile and run: `zig build run -- [input] [-o output]`
  - `input` and `output` are optional, in which case stdin and stdout will be used.
- Compile, then run: 
```
zig build
./zig-out/bin/archipelago_compiler [input] [-o output]
```
## Language format
- Every language construct looks like `{keyword}: {arg1} {arg2} ...`.
- There are generally three possible formats:
  -  `{keyword}:` <- this is used for certain control flow keywords.
  -  `{keyword}: {stack} {size?}` <- this is used for operations on the stacks.
  -  `{keyword}: {stack} {cmp} {stack}` <- this is used for comparison between the stacks.
  - `stack` must be either `a` or `b`, referring to the input and output stack respectively.
  - `size` must be a number, referring to the size of the stack to do the operation on. This argument can be omitted to use the default value.
  - `cmp` must be `>`, `=` or `<`.
## Keywords
- `ror: {stack} {size?}` <- rotate the top `size` elements of `stack`, sending the top one to the bottom. default `2`.
- `rol: {stack} {size?}` <- rotate the top `size` elements of `stack`, sending the bottom one to the top. default `2`.
- `add: {stack} {size?}` <- add together the top `size` elements of `stack`, default `2`.
- `sub: {stack} {size?}` <- subtract together the top `size` elements of `stack`, default `2`. The pattern (from the top) looks like `- + - + - + ...`
- `pop: {stack} {size?}` <- pop off the top `size` elements of `stack`, default `1`.
- `push: {stack} {size?}` <- pushes `size` copies of the first element of `stack`, default `1`.
- `send: {stack} {size?}` <- pushes and pops the top `size` elements of `stack`, default `1`.
- `inc: {stack} {size?}` <-increment the top element of `stack`, default `1`.
- `dec: {stack} {size?}` <- increment the top element of `stack`, default `1`.

- `end:` <- ends the current loop/if.
- `if: {stack} {cmp} {stack}` <- if the condition is met by the top elements of the `stack`s, does the following instructions.
- `else:` <- must go after an `if` statement. Creates the opposite branch.
- `while: {stack} {cmp} {stack}` <- repeats the following instructions until the condition is not met.
## Example: `max(a,b)`
```
send: a
if: a > b
  pop: b
  send: a
else:
  pop: a
end:
```
