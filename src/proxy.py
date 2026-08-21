"""Random proxy selection."""
import random


def get_random(proxies: list[str]) -> str:
    if not proxies:
        return ""
    return random.choice(proxies)


def proxy_flag(proxies: list[str]) -> str:
    proxy = get_random(proxies)
    return f"--proxy {proxy}" if proxy else ""
