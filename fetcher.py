import urllib.request

with urllib.request.urlopen('http://www.python.org/') as f:
    print(f.read(300).decode('utf-8'))
