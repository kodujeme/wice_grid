# encoding: UTF-8
module Wice
  module GridViewHelper

    # View helper for rendering the grid.
    #
    # The first parameter is a grid object returned by +initialize_grid+ in the controller.
    #
    # The second parameter is a hash of options:
    # * <tt>:html</tt> - a hash of HTML attributes to be included into the <tt>table</tt> tag.
    # * <tt>:class</tt> - a shortcut for <tt>:html => {:class => 'css_class'}</tt>
    # * <tt>:header_tr_html</tt> - a hash of HTML attributes to be included into the first <tt>tr</tt> tag
    #   (or two first <tt>tr</tt>'s if the filter row is present).
    # * <tt>:show_filters</tt> - defines when the filter is shown. Possible values are:
    #   * <tt>:when_filtered</tt> - the filter is shown when the current table is the result of filtering
    #   * <tt>:always</tt> or <tt>true</tt>  - show the filter always
    #   * <tt>:no</tt> or <tt>false</tt>     - never show the filter
    # * <tt>:upper_pagination_panel</tt> - a boolean value which defines whether there is an additional pagination
    #   panel on top of the table. By default it is false.
    # * <tt>:extra_request_parameters</tt> - a hash which will be added as additional HTTP request parameters to all
    #   links generated by the grid, be it sorting links, filters, or the 'Reset Filter' icon.
    #   Please note that WiceGrid respects and retains all request parameters already present in the URL which
    #   formed the page, so there is no need to enumerate them in <tt>:extra_request_parameters</tt>. A typical
    #   usage of <tt>:extra_request_parameters</tt> is a page with javascript tabs - changing the active tab
    #   does not reload the page, but if one such tab contains a WiceGrid, it could be required that if the user
    #   orders or filters the grid, the result page should have the tab with the grid activated. For this we
    #   need to send an additional parameter specifying from which tab the request was generated.
    # * <tt>:sorting_dependant_row_cycling</tt> - When set to true (by default it is false) the row styles +odd+
    #   and +even+ will be changed only when the content of the cell belonging to the sorted column changes.
    #   In other words, rows with identical values in the ordered column will have the same style (color).
    # * <tt>:allow_showing_all_records</tt> - allow or prohibit the "All Records" mode.
    # * <tt>:hide_reset_button</tt> - Do not show the default Filter Reset button.
    #   Useful when using a custom reset button.
    #   By default it is false.
    # * <tt>:hide_submit_button</tt> - Do not show the default Filter Submit button.
    #   Useful when using a custom submit button
    #   By default it is false.
    # * <tt>:hide_csv_button</tt> - a boolean value which defines whether the default Export To CSV button
    #   should be rendered. Useful when using a custom Export To CSV button.
    #   By default it is false.
    #   Please read README for more insights.
    #
    # The block contains definitions of grid columns using the +column+ method sent to the object yielded into
    # the block. In other words, the value returned by each of the blocks defines the content of a cell, the
    # first block is called for cells of the first column for each row (each ActiveRecord instance), the
    # second block is called for cells of the second column, and so on. See the example:
    #
    #   <%= grid(@accounts_grid, :html => {:class => 'grid_style', :id => 'accounts_grid'}, :header_tr_html => {:class => 'grid_headers'}) do |g|
    #
    #     g.column :name => 'Username', :attribute => 'username' do |account|
    #       account.username
    #     end
    #
    #     g.column :name => 'application_account.field.identity_id'._, :attribute => 'firstname', :model =>  Person do |account|
    #       link_to(account.identity.name, identity_path(account.identity))
    #     end
    #
    #     g.column do |account|
    #       link_to('Edit', edit_account_path(account))
    #     end
    #
    #   end -%>
    #
    #
    # Defaults for parameters <tt>:show_filters</tt> and <tt>:upper_pagination_panel</tt>
    # can be changed in <tt>lib/wice_grid_config.rb</tt> using constants <tt>Wice::Defaults::SHOW_FILTER</tt> and
    # <tt>WiceGrid::Defaults::SHOW_UPPER_PAGINATION_PANEL</tt>, this is convenient if you want to set a project wide setting
    # without having to repeat it for every grid instance.
    #
    # Pease read documentation about the +column+ method to achieve the enlightenment.

    def grid(grid, opts = {}, &block)
      # strip the method from HTML stuff
      unless grid.class == WiceGrid
        raise WiceGridArgumentError.new("The first argument for the grid helper must be an instance of the WiceGrid class")
      end

      if grid.output_buffer
        if grid.output_buffer == true
          raise  WiceGridException.new("Second occurence of grid helper with the same grid object. " +
                                "Did you intend to use detached filters and forget to define them?")
        else
          return grid.output_buffer
        end
      end

      options = {
        :allow_showing_all_records     => Defaults::ALLOW_SHOWING_ALL_QUERIES,
        :class                         => nil,
        :extra_request_parameters      => {},
        :header_tr_html                => {},
        :hide_reset_button             => false,
        :hide_submit_button            => false,
        :hide_csv_button               => false,
        :show_filters                  => Defaults::SHOW_FILTER,
        :sorting_dependant_row_cycling => false,
        :html                          => {},
        :upper_pagination_panel        => Defaults::SHOW_UPPER_PAGINATION_PANEL
      }

      opts.assert_valid_keys(options.keys)

      options.merge!(opts)

      options[:show_filters] = :no     if options[:show_filters] == false
      options[:show_filters] = :always if options[:show_filters] == true


      rendering = GridRenderer.new(grid, self)

      block.call(rendering) # calling block containing column() calls

      reuse_last_column_for_filter_buttons =
        Defaults::REUSE_LAST_COLUMN_FOR_FILTER_ICONS && rendering.last_column_for_html.capable_of_hosting_filter_related_icons?

      if grid.output_csv?
        content = grid_csv(grid, rendering)
      else
        # If blank_slate is defined we don't show any grid at all
        if rendering.blank_slate_handler &&  grid.resultset.size == 0 && ! grid.filtering_on?
          content = generate_blank_slate(grid, rendering)
          return content
        end

        content = grid_html(grid, options, rendering, reuse_last_column_for_filter_buttons)
      end

      grid.view_helper_finished = true
      content
    end

    def generate_blank_slate(grid, rendering) #:nodoc:
      buff = GridOutputBuffer.new

      buff <<  if rendering.blank_slate_handler.is_a?(Proc)
        call_block(rendering.blank_slate_handler, nil)
      elsif rendering.blank_slate_handler.is_a?(Hash)
        render(rendering.blank_slate_handler)
      else
        rendering.blank_slate_handler
      end

      if rendering.find_one_for(:in_html){|column| column.detach_with_id}
        buff.stubborn_output_mode = true
        buff.return_empty_strings_for_nonexistent_filters = true
        grid.output_buffer   = buff
      end
      buff
    end

    def call_block(block, ar, extra_argument = nil)  #:nodoc:
      extra_argument ? block.call(ar, extra_argument) : block.call(ar)
    end

    # the longest method? :(
    def grid_html(grid, options, rendering, reuse_last_column_for_filter_buttons) #:nodoc:

      table_html_attrs, header_tr_html = options[:html], options[:header_tr_html]

      table_html_attrs.add_or_append_class_value!('wice-grid', true)

      if Array === Defaults::DEFAULT_TABLE_CLASSES
        Defaults::DEFAULT_TABLE_CLASSES.each do |default_class|
          table_html_attrs.add_or_append_class_value!(default_class, true)
        end
      end

      if options[:class]
        table_html_attrs.add_or_append_class_value!(options[:class])
        options.delete(:class)
      end



      cycle_class = nil
      sorting_dependant_row_cycling = options[:sorting_dependant_row_cycling]

      content = GridOutputBuffer.new
      # Ruby 1.9.x
      content.force_encoding('UTF-8') if content.respond_to?(:force_encoding)

      content << %!<div class="wice-grid-container" id="#{grid.name}"><div id="#{grid.name}_title">!
      content << content_tag(:h3, grid.saved_query.name) if grid.saved_query
      content << "</div><table #{tag_options(table_html_attrs, true)}>"
      content << "<thead>"

      no_filters_at_all = (options[:show_filters] == :no || rendering.no_filter_needed?) ? true: false

      if no_filters_at_all
        no_rightmost_column = no_filter_row = no_filters_at_all
      else
        no_rightmost_column = no_filter_row = (options[:show_filters] == :no || rendering.no_filter_needed_in_main_table?) ? true: false
      end

      no_rightmost_column = true if reuse_last_column_for_filter_buttons

      number_of_columns = rendering.number_of_columns(:in_html)
      number_of_columns -= 1 if no_rightmost_column

      number_of_columns_for_extra_rows = number_of_columns + 1

      pagination_panel_content_html, pagination_panel_content_js = nil, nil
      if options[:upper_pagination_panel]
        content << rendering.pagination_panel(number_of_columns, options[:hide_csv_button]) do
          pagination_panel_content_html, pagination_panel_content_js =
            pagination_panel_content(grid, options[:extra_request_parameters], options[:allow_showing_all_records])
          pagination_panel_content_html
        end
      end

      title_row_attrs = header_tr_html.clone
      title_row_attrs.add_or_append_class_value!('wice-grid-title-row', true)

      content << %!<tr #{tag_options(title_row_attrs, true)}>!

      filter_row_id = grid.name + '_filter_row'

      # first row of column labels with sorting links

      filter_shown = if options[:show_filters] == :when_filtered
        grid.filtering_on?
      elsif options[:show_filters] == :always
        true
      end

      cached_javascript = []

      rendering.each_column_aware_of_one_last_one(:in_html) do |column, last|

        column_name = column.name

        if column.attribute && column.ordering

          css_class = grid.filtered_by?(column) ? 'active-filter' : nil

          direction = 'asc'
          link_style = nil
          if grid.ordered_by?(column)
            css_class = css_class.nil? ? 'sorted' : css_class + ' sorted'
            link_style = grid.order_direction
            direction = 'desc' if grid.order_direction == 'asc'
          end

          col_link = link_to(
            column_name,
            rendering.column_link(column, direction, params, options[:extra_request_parameters]),
            :class => link_style)
          content << content_tag(:th, col_link, Hash.make_hash(:class, css_class))
          column.css_class = css_class
        else
          if reuse_last_column_for_filter_buttons && last
            content << content_tag(:th,
              hide_show_icon(filter_row_id, grid, filter_shown, no_filter_row, options[:show_filters], rendering)
            )
          else
            content << content_tag(:th, column_name)
          end
        end
      end

      content << content_tag(:th,
        hide_show_icon(filter_row_id, grid, filter_shown, no_filter_row, options[:show_filters], rendering)
      ) unless no_rightmost_column

      content << '</tr>'
      # rendering first row end


      unless no_filters_at_all # there are filters, we don't know where, in the table or detached
        if no_filter_row # they are all detached
          content.stubborn_output_mode = true
          rendering.each_column(:in_html) do |column|
            if column.filter_shown?
              filter_html_code = column.render_filter
              filter_html_code = filter_html_code.html_safe_if_necessary
              content.add_filter(column.detach_with_id, filter_html_code)
            end
          end

        else # some filters are present in the table

          filter_row_attrs = header_tr_html.clone
          filter_row_attrs.add_or_append_class_value!('wg-filter-row', true)
          filter_row_attrs['id'] = filter_row_id

          content << %!<tr #{tag_options(filter_row_attrs, true)} !
          content << 'style="display:none"' unless filter_shown
          content << '>'

          rendering.each_column_aware_of_one_last_one(:in_html) do |column, last|
            if column.filter_shown?

              filter_html_code = column.render_filter
              filter_html_code = filter_html_code.html_safe_if_necessary
              if column.detach_with_id
                content.stubborn_output_mode = true
                content << content_tag(:th, '', Hash.make_hash(:class, column.css_class))
                content.add_filter(column.detach_with_id, filter_html_code)
              else
                content << content_tag(:th, filter_html_code, Hash.make_hash(:class, column.css_class))
              end
            else
              if reuse_last_column_for_filter_buttons && last
                content << content_tag(:th,
                  reset_submit_buttons(options, grid, rendering),
                  Hash.make_hash(:class, column.css_class).add_or_append_class_value!('filter_icons')
                )
              else
                content << content_tag(:th, '', Hash.make_hash(:class, column.css_class))
              end
            end
          end
          unless no_rightmost_column
            content << content_tag(:th, reset_submit_buttons(options, grid, rendering), :class => 'filter_icons' )
          end
          content << '</tr>'
        end
      end

      rendering.each_column(:in_html) do |column|
        unless column.css_class.blank?
          column.html.add_or_append_class_value!(column.css_class)
        end
      end

      content << '</thead><tfoot>'
      content << rendering.pagination_panel(number_of_columns, options[:hide_csv_button]) do
        if pagination_panel_content_html
          pagination_panel_content_html
        else
          pagination_panel_content_html, pagination_panel_content_js =
            pagination_panel_content(grid, options[:extra_request_parameters], options[:allow_showing_all_records])
          pagination_panel_content_html
        end
      end

      content << '</tfoot><tbody>'
      cached_javascript << pagination_panel_content_js

      # rendering  rows
      cell_value_of_the_ordered_column = nil
      previous_cell_value_of_the_ordered_column = nil

      grid.each do |ar| # rows

        before_row_output = if rendering.before_row_handler
          call_block(rendering.before_row_handler, ar, number_of_columns_for_extra_rows)
        else
          nil
        end

        after_row_output = if rendering.after_row_handler
          call_block(rendering.after_row_handler, ar, number_of_columns_for_extra_rows)
        else
          nil
        end

        row_content = ''
        rendering.each_column(:in_html) do |column|
          cell_block = column.cell_rendering_block

          opts = column.html.clone

          column_block_output = if column.class == ViewColumn.get_column_processor(:action)
            cell_block.call(ar, params)
          else
            call_block(cell_block, ar)
          end

          if column_block_output.kind_of?(Array)

            unless column_block_output.size == 2
              raise WiceGridArgumentError.new('When WiceGrid column block returns an array it is expected to contain 2 elements only - '+
                'the first is the contents of the table cell and the second is a hash containing HTML attributes for the <td> tag.')
            end

            column_block_output, additional_opts = column_block_output

            unless additional_opts.is_a?(Hash)
              raise WiceGridArgumentError.new('When WiceGrid column block returns an array its second element is expected to be a ' +
                "hash containing HTML attributes for the <td> tag. The returned value is #{additional_opts.inspect}. Read documentation.")
            end

            additional_css_class = nil
            if additional_opts.has_key?(:class)
              additional_css_class = additional_opts[:class]
              additional_opts.delete(:class)
            elsif additional_opts.has_key?('class')
              additional_css_class = additional_opts['class']
              additional_opts.delete('class')
            end
            opts.merge!(additional_opts)
            opts.add_or_append_class_value!(additional_css_class) unless additional_css_class.blank?
          end

          if sorting_dependant_row_cycling && column.attribute && grid.ordered_by?(column)
            cell_value_of_the_ordered_column = column_block_output
          end
          row_content += content_tag(:td, column_block_output, opts)
        end

        row_attributes = rendering.get_row_attributes(ar)

        if sorting_dependant_row_cycling
          cycle_class = cycle('odd', 'even', :name => grid.name) if cell_value_of_the_ordered_column != previous_cell_value_of_the_ordered_column
          previous_cell_value_of_the_ordered_column = cell_value_of_the_ordered_column
        else
          cycle_class = cycle('odd', 'even', :name => grid.name)
        end

        row_attributes.add_or_append_class_value!(cycle_class)

        content << before_row_output if before_row_output
        content << "<tr #{tag_options(row_attributes)}>#{row_content}"
        content << content_tag(:td, '') unless no_rightmost_column
        content << '</tr>'
        content << after_row_output if after_row_output
      end

      last_row_output = if rendering.last_row_handler
        call_block(rendering.last_row_handler, number_of_columns_for_extra_rows)
      else
        nil
      end

      content << last_row_output if last_row_output

      content << '</tbody></table>'

      base_link_for_filter, base_link_for_show_all_records = rendering.base_link_for_filter(controller, options[:extra_request_parameters])

      link_for_export      = rendering.link_for_export(controller, 'csv', options[:extra_request_parameters])

      parameter_name_for_query_loading = {grid.name => {:q => ''}}.to_query
      parameter_name_for_focus = {grid.name => {:foc => ''}}.to_query

      processor_initializer_arguments = [base_link_for_filter, base_link_for_show_all_records,
        link_for_export, parameter_name_for_query_loading, parameter_name_for_focus, Rails.env]

      filter_declarations = if no_filters_at_all
        []
      else
        rendering.select_for(:in_html) do |vc|
          vc.attribute && vc.filter
        end.collect{|column| column.yield_declaration}
      end

      wg_data = {
        'data-processor-initializer-arguments' => processor_initializer_arguments.to_json,
        'data-filter-declarations'             => filter_declarations.to_json,
        :class                                 => 'wg-data'
      }

      wg_data['data-foc'] = grid.status['foc'] if grid.status['foc']

      content << content_tag(:div, '', wg_data)

      content << '</div>'

      js_loaded_check  = if Rails.env == 'development'
        %$ if (typeof(WiceGridProcessor) == "undefined"){\n$ +
        %$   alert("wice_grid.js not loaded, WiceGrid cannot proceed!\\n" +\n$ +
        %$     "Make sure that you have loaded wice_grid.js.\\n" +\n$ +
        %$     "Add line\\n//= require wice_grid.js\\n" +\n$ +
        %$     "to app/assets/javascripts/application.js")\n$ +
        %$ }\n$
      else
        ''
      end

      # if rendering.csv_export_icon_present
      #   cached_javascript << JsAdaptor.csv_export_icon_initialization(grid.name)
      # end


      if Wice::ConfigurationProvider.value_for(:SECOND_RANGE_VALUE_FOLLOWING_THE_FIRST) && rendering.contains_range_filters
        cached_javascript << JsAdaptor.update_ranges(grid.name)
      end

      content << javascript_tag(
        JsAdaptor.dom_loaded + cached_javascript.compact.join('') + '})'
      )

      if content.stubborn_output_mode
        grid.output_buffer = content
      else
        # this will serve as a flag that the grid helper has already processed the grid but in a normal mode,
        # not in the mode with detached filters.
        grid.output_buffer = true
      end
      return content
    end

    def hide_show_icon(filter_row_id, grid, filter_shown, no_filter_row, show_filters, rendering)  #:nodoc:
      grid_name = grid.name
      no_filter_opening_closing_icon = (show_filters == :always) || no_filter_row

      styles = ["display: block;", "display: none;"]
      styles.reverse! unless filter_shown


      if no_filter_opening_closing_icon
        hide_icon = show_icon = ''
      else

        content_tag(:div, '',
          :title => NlMessage['hide_filter_tooltip'],
          :style => styles[0],
          :class => 'clickable  wg-hide-filter'
        ) +

        content_tag(:div, '',
          :title => NlMessage['show_filter_tooltip'],
          :style => styles[1],
          :class => 'clickable  wg-show-filter'
        )

      end
    end

    def reset_submit_buttons(options, grid, rendering)  #:nodoc:
      (if options[:hide_submit_button]
        ''
      else
        content_tag(:div, '',
          :title => NlMessage['filter_tooltip'],
          :id => grid.name + '_submit_grid_icon',
          :class => 'submit clickable'
        )
      end + ' ' +
      if options[:hide_reset_button]
        ''
      else

        content_tag(:div, '',
          :title => NlMessage['reset_filter_tooltip'],
          :id => grid.name + '_reset_grid_icon',
          :class => 'reset clickable'
        )
      end).html_safe_if_necessary
    end

    # Renders a detached filter. The parameters are:
    # * +grid+ the WiceGrid object
    # * +filter_key+ an identifier of the filter specified in the column declaration by parameter +:detach_with_id+
    def grid_filter(grid, filter_key)
      unless grid.kind_of? WiceGrid
        raise WiceGridArgumentError.new("grid_filter: the parameter must be a WiceGrid instance.")
      end
      if grid.output_buffer.nil?
        raise WiceGridArgumentError.new("grid_filter: You have attempted to run 'grid_filter' before 'grid'. Read about detached filters in the documentation.")
      end
      if grid.output_buffer == true
        raise WiceGridArgumentError.new("grid_filter: You have defined no detached filters, or you try use detached filters with" +
          ":show_filters => :no (set :show_filters to :always in this case). Read about detached filters in the documentation.")
      end

      content_tag :span,
        grid.output_buffer.filter_for(filter_key),
        :class => "wg-detached-filter #{grid.name}_detached_filter",
        'data-grid-name' => grid.name
    end


    def grid_csv(grid, rendering) #:nodoc:

      spreadsheet = ::Wice::Spreadsheet.new(grid.name, grid.csv_field_separator)

      # columns
      spreadsheet << rendering.column_labels(:in_csv)

      # rendering  rows
      grid.each do |ar| # rows
        row = []

        rendering.each_column(:in_csv) do |column|
          cell_block = column.cell_rendering_block

          column_block_output = call_block(cell_block, ar)

          if column_block_output.kind_of?(Array)
            column_block_output, additional_opts = column_block_output
          end

          row << column_block_output
        end
        spreadsheet << row
      end
      grid.csv_tempfile = spreadsheet.tempfile
      return grid.csv_tempfile.path
    end

    def pagination_panel_content(grid, extra_request_parameters, allow_showing_all_records) #:nodoc:
      extra_request_parameters = extra_request_parameters.clone
      if grid.saved_query
        extra_request_parameters["#{grid.name}[q]"] = grid.saved_query.id
      end

      html, js = pagination_info(grid, allow_showing_all_records)

      [will_paginate(grid.resultset,
        :previous_label => NlMessage['previous_label'],
        :next_label     => NlMessage['next_label'],
        :param_name     => "#{grid.name}[page]",
        :renderer       => ::Wice::WillPaginatePaginator,
        :params         => extra_request_parameters).to_s +
        (' <div class="pagination_status">' + html + '</div>').html_safe_if_necessary, js]
    end


    def show_all_link(collection_total_entries, parameters, grid_name) #:nodoc:

      message = NlMessage['all_queries_warning']
      confirmation = collection_total_entries > Defaults::START_SHOWING_WARNING_FROM ? message : nil

      html = content_tag(:a, NlMessage['show_all_records_label'],
        :href=>"#",
        :title => NlMessage['show_all_records_tooltip'],
        :class => 'wg-show-all-link',
        'data-grid-state' => parameters.to_json,
        'data-confim-message' => confirmation
      )

      [html, '']
    end

    def back_to_pagination_link(parameters, grid_name) #:nodoc:
      pagination_override_parameter_name = "#{grid_name}[pp]"
      parameters = parameters.reject{|k, v| k == pagination_override_parameter_name}

      html = content_tag(:a, NlMessage['switch_back_to_paginated_mode_label'],
        :href=>"#",
        :title => NlMessage['switch_back_to_paginated_mode_tooltip'],
        :class => 'wg-back-to-pagination-link',
        'data-grid-state' => parameters.to_json
      )

      [html, '']
    end

    def pagination_info(grid, allow_showing_all_records)  #:nodoc:
      collection = grid.resultset

      collection_total_entries = collection.total_entries
      collection_total_entries_str = collection_total_entries.to_s
      parameters = grid.get_state_as_parameter_value_pairs

      js = ''
      html = if (collection.total_pages < 2 && collection.length == 0)
        '0'
      else
        parameters << ["#{grid.name}[pp]", collection_total_entries_str]

        "#{collection.offset + 1}-#{collection.offset + collection.length} / #{collection_total_entries_str} " +
          if (! allow_showing_all_records) || collection_total_entries <= collection.length
            ''
          else
            res, js = show_all_link(collection_total_entries, parameters, grid.name)
            res
          end
      end +
      if grid.all_record_mode?
        res, js = back_to_pagination_link(parameters, grid.name)
        res
      else
        ''
      end

      [html, js]
    end

  end
end
