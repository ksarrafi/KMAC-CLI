"""KmacAgent engine entry point.

Run as:  PYTHONPATH=scripts python3 -m _agent_engine <command>
"""

import os
import sys

_pkg_dir = os.path.dirname(os.path.abspath(__file__))
_parent = os.path.dirname(_pkg_dir)
if _parent not in sys.path:
    sys.path.insert(0, _parent)


def main():
    args = sys.argv[1:]
    cmd = args[0] if args else "daemon"

    if cmd in ("daemon", "run"):
        from _agent_engine.daemon import run_daemon
        run_daemon()

    elif cmd == "ping":
        from _agent_engine.client import send_request
        try:
            send_request("ping", [])
        except SystemExit:
            sys.exit(1)

    elif cmd == "chat":
        from _agent_engine.client import chat_interactive
        agent, session, model = "default", "", ""
        i = 1
        while i < len(sys.argv):
            if sys.argv[i] in ("-a", "--agent") and i + 1 < len(sys.argv):
                agent = sys.argv[i + 1]; i += 2
            elif sys.argv[i] in ("-s", "--session") and i + 1 < len(sys.argv):
                session = sys.argv[i + 1]; i += 2
            elif sys.argv[i] in ("-m", "--model") and i + 1 < len(sys.argv):
                model = sys.argv[i + 1]; i += 2
            else:
                i += 1
        chat_interactive(agent, session, model)

    else:
        from _agent_engine.client import send_request
        send_request(cmd, args[1:])


if __name__ == "__main__":
    main()
