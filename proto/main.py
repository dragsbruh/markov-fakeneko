from collections import Counter, defaultdict

import random
import time
import sys
import os


class Node:
    def __init__(self):
        self.weights = Counter()


class FakeNeko:
    def __init__(self, depth: int):
        self.depth = depth
        self.nodes = defaultdict(Node)

    def _initial_sequence(self):
        return "\0" * self.depth

    def get_node(self, sequence: str):
        return self.nodes[sequence]

    def record(self, text: str):
        sequence = self._initial_sequence()

        for char in text:
            node = self.get_node(sequence)
            node.weights[char] += 1
            sequence = sequence[1:] + char

    def generate(self):
        sequence = self._initial_sequence()

        while True:
            node = self.get_node(sequence)
            if not node.weights:
                break

            chars, weights = zip(*node.weights.items())
            next_char = random.choices(chars, weights)[0]

            yield next_char
            sequence = sequence[1:] + next_char


def train(fn: FakeNeko, sentences: list[str]):
    target = len(sentences)
    for i, line in enumerate(sentences):
        if i > target:
            break

        fn.record(line.strip())


def main():
    if len(sys.argv) < 3:
        print("usage:", sys.argv[0], "<depth>", "[...files]")
        exit(1)

    depth = sys.argv[1]
    try:
        depth = int(depth)
    except ValueError:
        print("error: provided depth is not a number")
        exit(1)

    input_files = sys.argv[2:]
    for file in input_files:
        if not os.path.exists(file):
            print("error: file", file, "does not exist")
            exit(1)

    fn = FakeNeko(depth)

    global_start = time.time_ns()
    sample_times = []
    for file in input_files:
        with open(file, "r") as f:
            lines = f.readlines()
            for i, line in enumerate(lines, start=1):
                start = time.time_ns()
                fn.record(line)
                print(
                    f"{i}/{len(lines)} training status {round((i/len(lines))*100, 2)}%", end='\r')
                sample_times.append(time.time_ns()-start)
                time.sleep(0.001)
            print()

    duration = (time.time_ns()-global_start)/1_000_000_000
    iter_avg = (sum(sample_times)/len(sample_times))/1_000_000_000
    print("training complete in", duration,
          "seconds with each iteration averaging", iter_avg, "seconds")

    for i, char in enumerate(fn.generate()):
        sys.stdout.write(char)
        if i % 6 == 0:
            sys.stdout.flush()
    sys.stdout.flush()


if __name__ == "__main__":
    main()
