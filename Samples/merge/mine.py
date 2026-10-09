import json
import sys


def load(path):
    with open(path) as f:
        return json.load(f)


def greet(name):
    return "hello, " + name + "!"


def main():
    data = load(sys.argv[1] if len(sys.argv) > 1 else "config.json")
    print(greet(data["name"]))


if __name__ == "__main__":
    main()
