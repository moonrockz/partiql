///|
test "YAML documents interoperate with public value constructors" {
  @expect.expect(@partiql_yaml.read_text("name: Ada\nitems: [1, 2]")).to_equal([
    @value.Value::from_tuple(
      @value.Tuple([
        ("name", @value.Value::from_string("Ada")),
        (
          "items",
          @value.Value::from_list([
            @value.Value::from_int(1),
            @value.Value::from_int(2),
          ]),
        ),
      ]),
    ),
  ])
}
