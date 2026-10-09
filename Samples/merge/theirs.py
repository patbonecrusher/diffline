import json
import logging


def load(path):
    logging.info("loading %s", path)
    with open(path) as f:
        return json.load(f)


def greet(name):
    return f"Hi {name}"


def main():
    data = load("config.json")
    print(greet(data["name"]))


if __name__ == "__main__":
    main()
