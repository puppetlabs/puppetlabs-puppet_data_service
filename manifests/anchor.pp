# @api private
class puppet_data_service::anchor {
  assert_private()

  # This class exists only to contain a dependency anchor
  anchor { 'puppet_data_service': }
}
