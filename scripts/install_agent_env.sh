#!/bin/bash

git clone https://github.com/roundpilot/superpowers ~/.gemini/config/plugins/superpowers

# Skills related
npx skills add https://github.com/vercel-labs/skills -y -g --skill find-skills

# Google & GCP skils
#npx skills add https://github.com/google/skills -y -g

for d in ~/.agents/skills/*/; \
do [ -d "$d" ] && rm -rf "$HOME/.gemini/skills/$(basename "$d")"; \
done && cp -a ~/.agents/skills/* ~/.gemini/skills/
