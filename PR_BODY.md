## Summary

Tighten the README around a simpler local-first onboarding story.

This PR:
- leads with the concrete problem (`recreating the same agents/skills across tools and machines`)
- makes `init --local` the first quick-start path
- adds a simple command chooser (`init`, `push`, `join`, `clone`, `sync`)
- explains what `teamrc sync` actually does
- moves relay complexity lower without removing it
- keeps the tone practical instead of salesy

## Why

The current README is directionally good, but it still introduces too many concepts before the first payoff lands. For a new user, the highest-trust story is:

1. no server required
2. local-only works
3. `sync` writes native files into the installed tools
4. relay/team sync is optional later

This rewrite tries to make that sequence obvious.

## Notes

- README-only change
- no code or behavior changes
- based on prior multi-angle review (maintainer/editor, skeptical new user, onboarding/growth)
