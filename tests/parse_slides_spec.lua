---@diagnostic disable: undefined-global, undefined-field

local parse = require('present')._parse_slides
describe('present.parse_slides', function()
  it(
    'should parse and empty file',
    function()
      assert.are.same({ slides = {
        { title = '', body = {} },
      } }, parse {})
    end
  )

  it(
    'should parse a file with one slide',
    function()
      assert.are.same(
        { slides = {
          { title = '# This is the first slide', body = { 'This is the body' } },
        } },
        parse {
          '# This is the first slide',
          'This is the body',
        }
      )
    end
  )
end)
