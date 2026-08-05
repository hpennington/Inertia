#!/usr/bin/env bash
rm -rf ../docs
mkdocs build
mv site ../docs/
