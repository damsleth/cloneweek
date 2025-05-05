# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview
Cloneweek is a shell script that clones Microsoft 365 calendar events from a previous week to the current week using the Microsoft Graph API.

## Environment
- macOS only (uses macOS-specific date commands)
- Requires: zsh, curl, jq, ncat

## Commands
- Run script: `./cloneweek.zsh`
- Usage with options: `./cloneweek.zsh --from-week <week> --to-week <week> --categories <categories>`
- Dry run mode: `./cloneweek.zsh --dry-run`

## Code Style Guidelines
- Shell script conventions: 
  - Use snake_case for variables
  - Log levels: INFO, DEBUG, ERROR
  - Store configuration in .env file
  - Error handling with proper exit codes
- General:
  - Detailed comments for functions
  - Use descriptive variable names
  - Include debug/verbose logging options
  - Proper exit codes and error handling

## Script Organization
- `cloneweek.zsh`: Main script for cloning events
- `get_token.zsh`: OAuth authentication utility
- Configuration via .env file (copy from .env.sample)