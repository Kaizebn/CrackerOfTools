"""Interface en ligne de commande de JARVIS (utilisée par run.py et le script `jarvis`)."""

from __future__ import annotations

import argparse
import asyncio

from jarvis.app import AppOptions, ConfigError, run_text, run_voice_headless, run_with_qt
from jarvis.config import get_settings
from jarvis.logging_config import configure_logging, get_logger


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="JARVIS — assistant IA vocal pour Windows")
    parser.add_argument("--text", action="store_true", help="Mode texte (clavier), sans audio ni UI.")
    parser.add_argument("--no-ui", action="store_true", help="Mode vocal sans interface graphique.")
    parser.add_argument("--dry-run", action="store_true", help="Simule les actions risquées sans les exécuter.")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> None:
    args = parse_args(argv)
    settings = get_settings()
    configure_logging(settings.log_level, settings.log_dir)
    log = get_logger("jarvis.boot")
    log.info(
        "jarvis.starting",
        model=settings.model,
        mode=_mode_name(args),
        dry_run=args.dry_run or settings.dry_run,
    )

    options = AppOptions(text=args.text, ui=not args.no_ui and not args.text, dry_run=args.dry_run)

    try:
        if args.text:
            asyncio.run(run_text(settings, options))
        elif options.ui and settings.ui_enabled:
            run_with_qt(settings, options)
        else:
            asyncio.run(run_voice_headless(settings, options))
    except ConfigError as exc:
        log.error("jarvis.config_error", error=str(exc))
        print(f"\n⚠️  {exc}")
    except KeyboardInterrupt:
        log.info("jarvis.interrupted")


def _mode_name(args: argparse.Namespace) -> str:
    if args.text:
        return "text"
    return "voice-no-ui" if args.no_ui else "voice-ui"
