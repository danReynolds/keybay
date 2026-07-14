# Keyway CLI demos

These demos show Keyway at the process boundary of three common development
workflows:

- [`flutter`](flutter): inject a test credential into a Flutter widget test
- [`rails`](rails): boot a Rails application and run application code
- [`node`](node): start a Node HTTP service

Each directory commits its `.secrets.env`. The files contain public
configuration and `kw://` references only; every developer supplies their own
values through the local Keyway store.

Run commands from the selected demo directory. Keyway deliberately reads only
that directory's manifest and never searches parent directories. The demos use
different qualified namespaces, so their disposable values do not bleed into
one another.

Install `keyway`, then follow the README in one of the directories. Remove its
disposable value with the documented `keyway rm` command when finished.
