"""
cli/all_handler.py — Generalized -all flag handler
Wraps single-item handlers to work with -all flag
"""


def handle_all(name: str, mnt: str, handler_func, *args, **kwargs) -> None:
    """
    If name is empty and all_=True, apply handler to all matching items.
    Otherwise, apply handler to the single name.

    Args:
        name: The item name/identifier (or empty string if -all)
        mnt: The mount point
        handler_func: The function to call (signature: func(name, mnt, *args, **kwargs))
        *args: Additional positional arguments
        **kwargs: Additional keyword arguments
    """
    all_ = kwargs.pop('all_', False)

    if all_ and not name:
        # Get all containers and apply handler to each
        from engine.container.list import list_containers
        containers = list_containers(mnt, return_data=True)
        if containers:
            for container in containers:
                try:
                    handler_func(container.get('name') or container, mnt, *args, **kwargs)
                except Exception:
                    pass
    else:
        # Apply to single item
        handler_func(name, mnt, *args, **kwargs)
