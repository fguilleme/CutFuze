#!/bin/sh
# Refresh offline app resources from the public documentation and screenshots.
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
for task_document in UserGuide.fr UserGuide.en Tutorial.fr Tutorial.en; do
    cp "$task_root/Docs/$task_document.md" "$task_root/CutFuze/Help/$task_document.md"
done
for task_language in fr en; do
    cp "$task_root/Docs/AppStore/Screenshots-iPhone-6.1-6.3-2026-10-09/iPhone-6.3/$task_language/01-montage.png" "$task_root/CutFuze/Help/help-iphone-$task_language.png"
    cp "$task_root/Docs/AppStore/Screenshots-2026-10-09/iPad/$task_language/01-montage.png" "$task_root/CutFuze/Help/help-ipad-$task_language.png"
done
