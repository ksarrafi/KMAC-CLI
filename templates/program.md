# Research Program

This is an autonomous experiment runner managed by KMac CLI.
Inspired by [karpathy/autoresearch](https://github.com/karpathy/autoresearch).

## Configuration

- **Tag**: SET_BY_INIT
- **Target file**: SET_BY_INIT
- **Eval command**: `SET_BY_INIT`
- **Metric pattern**: `SET_BY_INIT`
- **Direction**: lower is better
- **Time budget**: 300s per experiment

## Goal

Improve the target metric through iterative experimentation.

## Rules

**What the AI CAN do:**
- Modify the target file — this is the only file it edits
- Change architecture, algorithms, hyperparameters, data handling — anything in scope

**What the AI CANNOT do:**
- Modify any other files
- Install new dependencies
- Change the evaluation method

## Experiment Loop

1. Read the current state of the target file
2. Propose a change with a clear hypothesis
3. Apply the change
4. Run the eval command
5. Check the metric
6. If improved → keep (git commit). If not → discard (git reset)
7. Log results to results.tsv
8. Repeat indefinitely

## Simplicity Criterion

All else being equal, simpler is better. A small improvement that adds ugly complexity
is not worth it. Removing code and getting equal or better results is a win.

## Strategy Guide

When proposing experiments, consider:

- **Low-hanging fruit first**: Fix obvious inefficiencies before trying radical changes
- **One variable at a time**: Isolate changes so you know what helped
- **Learn from failures**: If increasing X failed, don't try it again at a bigger scale
- **Combine winners**: After finding two improvements, try combining them
- **Simplify**: Periodically try removing complexity — simpler code that matches performance is a win
- **Read the code carefully**: Often the biggest gains come from understanding what's already there

## Notes

- The first run should always establish the baseline (run without modifications)
- If a run crashes, attempt a fix. After 5 consecutive failures, try a different approach
- Never pause to ask the human — run autonomously until manually stopped
