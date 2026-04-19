from __future__ import annotations

import argparse
import json

from app.chat import ChatService
from app.config import load_config
from app.history import clear_history, delete_history_item, get_history_item, list_history
from app.ingest import ingest_paths
from app.models import ChatRequest


def main() -> None:
    parser = argparse.ArgumentParser(description="Local-first chatbot CLI.")
    parser.add_argument("--config", default=None, help="Path to config.yml.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    ask = subparsers.add_parser("ask", help="Ask one question.")
    ask.add_argument("message")
    ask.add_argument("--provider", default=None)
    ask.add_argument("--model", default=None)
    ask.add_argument("--retrieval-profile", default=None)
    ask.add_argument("--no-rag", action="store_true")
    ask.add_argument("--rag-only", action="store_true")
    ask.add_argument("--local-files", action="store_true", help="Use configured local file sources only.")
    ask.add_argument("--web-search", action="store_true")
    ask.add_argument("--force-llm", action="store_true")
    ask.add_argument("--json", action="store_true")

    shell = subparsers.add_parser("shell", help="Start an interactive shell.")
    shell.add_argument("--provider", default=None)
    shell.add_argument("--model", default=None)
    shell.add_argument("--retrieval-profile", default=None)
    shell.add_argument("--no-rag", action="store_true")
    shell.add_argument("--rag-only", action="store_true")
    shell.add_argument("--local-files", action="store_true", help="Use configured local file sources only.")
    shell.add_argument("--web-search", action="store_true")

    ingest = subparsers.add_parser("ingest", help="Ingest documents into SQLite and optional Qdrant.")
    ingest.add_argument("paths", nargs="+")
    ingest.add_argument("--reset", action="store_true")
    ingest.add_argument("--profiles", default=None, help="Comma-separated retrieval profiles to ingest.")

    compare = subparsers.add_parser("compare", help="Ask one question against multiple retrieval profiles.")
    compare.add_argument("message")
    compare.add_argument("--profiles", required=True, help="Comma-separated retrieval profiles to compare.")
    compare.add_argument("--provider", default=None)
    compare.add_argument("--model", default=None)
    compare.add_argument("--force-llm", action="store_true")

    history = subparsers.add_parser("history", help="Show or clear question history.")
    history_actions = history.add_subparsers(dest="history_command")
    history_list = history_actions.add_parser("list", help="List recent questions.")
    history_list.add_argument("--limit", type=int, default=50)
    history_show = history_actions.add_parser("show", help="Show one history item.")
    history_show.add_argument("id", type=int)
    history_delete = history_actions.add_parser("delete", help="Delete one history item.")
    history_delete.add_argument("id", type=int)
    history_actions.add_parser("clear", help="Clear all history.")

    args = parser.parse_args()
    config = load_config(args.config)

    if args.command == "ingest":
        result = ingest_paths(config, args.paths, reset=args.reset, profiles=split_profiles(args.profiles))
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return

    if args.command == "history":
        command = args.history_command or "list"
        if command == "list":
            for item in list_history(config, limit=args.limit):
                print(f"{item['id']}  {item['created_at_iso']}  {item['source']}  {item['message']}")
        elif command == "show":
            print(json.dumps(get_history_item(config, args.id), indent=2, ensure_ascii=False))
        elif command == "delete":
            print(json.dumps({"deleted": delete_history_item(config, args.id)}, indent=2, ensure_ascii=False))
        elif command == "clear":
            print(json.dumps({"deleted": clear_history(config)}, indent=2, ensure_ascii=False))
        return

    service = ChatService(config)
    if args.command == "compare":
        result = service.compare(
            ChatRequest(
                message=args.message,
                provider=args.provider,
                model=args.model,
                force_llm=args.force_llm,
            ),
            split_profiles(args.profiles) or [],
        )
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return

    if args.command == "ask":
        response = service.answer(
            ChatRequest(
                message=args.message,
                provider=args.provider,
                model=args.model,
                retrieval_profile=args.retrieval_profile,
                use_rag=(not args.no_rag or args.rag_only) and not args.local_files,
                rag_only=args.rag_only,
                use_local_files=args.local_files,
                use_web_search=args.web_search,
                force_llm=args.force_llm,
            )
        )
        if args.json:
            print(json.dumps(response.__dict__, indent=2, ensure_ascii=False))
        else:
            print(response.answer)
            print(f"\nsource={response.source} provider={response.provider} model={response.model} tool={response.tool}")
        return

    print("Type 'exit' or Ctrl-D to quit.")
    while True:
        try:
            message = input("> ").strip()
        except EOFError:
            print()
            break
        if message.lower() in {"exit", "quit"}:
            break
        response = service.answer(
            ChatRequest(
                message=message,
                provider=args.provider,
                model=args.model,
                retrieval_profile=args.retrieval_profile,
                use_rag=(not args.no_rag or args.rag_only) and not args.local_files,
                rag_only=args.rag_only,
                use_local_files=args.local_files,
                use_web_search=args.web_search,
            )
        )
        print(response.answer)
        print(f"source={response.source}\n")


def split_profiles(value: str | None) -> list[str] | None:
    if not value:
        return None
    return [item.strip() for item in value.split(",") if item.strip()]


if __name__ == "__main__":
    main()
