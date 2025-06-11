import re


def _check_key(key:str) -> str:
    """
    Check if a key is valid
    """
    key = key.strip().lower()
    if key[0] == "_":
        raise ValueError(f"Key {key} cannot start with an underscore")
    
    allowed = re.compile(r"^[a-z_][a-z0-9_]*$")
    if not allowed.match(key):
        raise ValueError(f"Key {key} contains invalid characters")
    
    return key


def _check_value(value:str) -> str:
    """
    Check if a value is valid
    """
    value = value.strip()
    value = _check_value(value)
    if value[0] == "_":
        raise ValueError(f"Value {value} cannot start with an underscore")
    
    return value


def _parse_array(value:str) -> list:
    """
    Parse an array
    """
    value = value.strip()
    
    if value[0] != "[" or value[-1] != "]":
        raise ValueError("Array must be enclosed in square brackets")
    
    value = value[1:-1]
    values = value.split(",")
    values = [_parse_value(v) for v in values]
    return values

def _parse_value(value:str) -> any:
    """
    Parse a value
    """
    
    if value[0] == "[" and value[-1] == "]":
        return _parse_array(value)
    
    
    if value.lower() == "true":
        return True
    if value.lower() == "false":
        return False
    try:
        return int(value)
    except ValueError:
        pass
    try:
        return float(value)
    except ValueError:
        pass
    return value

def parse(text:str) -> dict:
    """
    Parse a YAML string into a dictionary
    """
    lines = text.split("\n")
    data = {}
    for line in lines:
        
        line = line.split("#")[0]
        line = line.strip()
        if line == "":
            continue

        key, value = line.split(":", maxsplit=1)
        key = _check_key(key)

        value = _parse_value(value)
        data[key] = value
    return data


def parse_file(file:str) -> dict:
    """
    Parse a YAML file into a dictionary
    """
    with open(file, "r") as f:
        text = f.read()
    return parse(text)

def dump(data:dict) -> str:
    """
    Dump a dictionary into a YAML string
    """
    text = ""
    for key, value in data.items():
        text += f"{key}: {value}\n"
    return text

def dump_file(data:dict, file:str):
    """
    Dump a dictionary into a YAML file
    """
    text = dump(data)
    with open(file, "w") as f:
        f.write(text)