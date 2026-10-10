cache = true
ignore = {
    "212/self",
    "211",
    "212",
    "411/Shadowing",
    "412/Shadowing",
    "542/Empty if",
}
max_line_length = 120
globals = {
    "ngx",
}
files["spec/"] = {
    ignore = {
        "211",
        "212",
        "411/Shadowing",
        "412/Shadowing",
        "231",
    },
}
files["src/"] = {
    read_globals = {
        "ngx",
    },
    ignore = {
        "211",
        "212",
    },
}
