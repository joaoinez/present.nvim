---@diagnostic disable: undefined-global, undefined-field

local parse = require('present')._parse_slides
describe('present.parse_slides', function()
  it(
    'should parse and empty file',
    function()
      assert.are.same({
        slides = {
          {
            title = '',
            body = {},
            blocks = {},
          },
        },
      }, parse {})
    end
  )

  it(
    'should parse a file with one slide',
    function()
      assert.are.same(
        {
          slides = {
            {
              title = '# This is the first slide',
              body = { 'This is the body' },
              blocks = {},
            },
          },
        },
        parse {
          '# This is the first slide',
          'This is the body',
        }
      )
    end
  )

  it('should parse a file with one slide and a block', function()
    local parsed = parse {
      '# This is the first slide',
      'This is the body',
      '```lua',
      "print('hi')",
      '```',
    }
    local slide = parsed.slides[1]

    assert.are.same('# This is the first slide', slide.title)
    assert.are.same({ 'This is the body', '```lua', "print('hi')", '```' }, slide.body)
    assert.are.same({ {
      language = 'lua',
      body = vim.trim [[print('hi')]],
    } }, slide.blocks)
  end)
end)
