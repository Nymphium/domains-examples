type t = bool Mvar.t

let create_false () = Mvar.create false
let create_true () = Mvar.create true
let enable t = Mvar.modify t @@ Fun.const true
let disable t = Mvar.modify t @@ Fun.const false
let is_enabled t = Mvar.compare t true
let is_disabled t = Mvar.compare t false
