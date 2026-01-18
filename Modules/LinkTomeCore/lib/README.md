# NCrontab.Advanced Library

This directory should contain the NCrontab.Advanced.dll library for proper cron schedule evaluation.

## Installation

Download NCrontab.Advanced.dll and place it in this directory.

The library is used for:
- Parsing 5-field and 6-field cron expressions
- Calculating next occurrences within time windows
- Accurate schedule evaluation for timer functions

## Version

Compatible with NCrontab.Advanced (any recent version should work)

## Alternative

If you don't have the DLL, the timer infrastructure will still load but schedule evaluation may not work correctly. The DLL must be provided separately.
