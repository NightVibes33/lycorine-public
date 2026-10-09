# uicache

Forked from ProcursusTeam/uikittools-ng, commit
6b84d79261186d070b54efa9a39850f108b52239:
https://github.com/ProcursusTeam/uikittools-ng/tree/6b84d79261186d070b54efa9a39850f108b52239

Upstream licensing is retained in LICENSE. Local changes:

- Invalid bundle metadata fails without attempting unregistration.
- Embedded registration uses LSOperationRequestContext with targetUserID 501.
- Registration checks the saved bundle path and application type.
- Failures propagate to the command exit status.
- Global -a operations cannot be combined with individual -p/-u operations;
  -f requires -a. No implicit database rebuild or respring.
