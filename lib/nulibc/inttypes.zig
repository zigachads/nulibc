pub const intmax_t = c_long;

pub const imaxdiv_t = struct {
    quot: intmax_t,
    rem: intmax_t,
};
