return {
    'goolord/alpha-nvim',
    config = function ()
        local dashboard = require('alpha.themes.dashboard')
        dashboard.section.buttons.val = {
            dashboard.button('e', 'New file', '<cmd>enew<CR>'),
            dashboard.button('SPC f f', 'Find files', '<cmd>Telescope find_files<CR>'),
            dashboard.button('r', 'Recently opened files', '<cmd>Telescope oldfiles<CR>'),
            dashboard.button('SPC f g', 'Search text', '<cmd>Telescope live_grep<CR>'),
            dashboard.button('SPC f b', 'Open buffers', '<cmd>Telescope buffers<CR>'),
            dashboard.button('SPC f h', 'Help tags', '<cmd>Telescope help_tags<CR>'),
        }
        require('alpha').setup(dashboard.config)
    end
}
