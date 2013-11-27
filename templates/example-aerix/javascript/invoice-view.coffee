class Nota.Templates.AerixInvoiceView extends Nota.InvoiceView

  # Pretty much everything apart from the table
  _renderInvoiceDetails: ->
    directives = 
      vatPercentage: =>
        @model.get("vatPercentage")*100
      companyFullname: =>
        origin = @model.get('origin') 
        origin.companyName+' '+origin.companyLawform

    @_mapObjToDOM @model.attributes, @$el, directives, false
    
    @_mapObjToDOM @model.get("client"), @$('p#client-block')
    @_mapObjToDOM @model.get("origin"), @$('div.company-info, footer')

    @$(".email").attr 'href', 'mailto:'+@model.get("origin").email
    @$(".website").attr 'href', 'http://'+@model.get("origin").email
    
    date = new Date(@model.get('meta').date)
    fullID = date.getUTCFullYear()+'.'+_.str.pad(@model.get('meta').id.toString(), 4, '0')
    @$('#invoice-id').html fullID
    $("html head title").html 'Invoice '+fullID

    monthNames = [ "januari", "feruari", "maart", "april", "mei", "juni",
        "juli", "augustus", "september", "october", "november", "december" ]
    month = monthNames[date.getMonth()]
    year = date.getUTCFullYear()
    day = date.getUTCDate()
    # Next step might seem overkill, but think of peculiar cases like end of the year flips
    date.setUTCDate day + @model.get('validityPeriod')
    validMonth = monthNames[date.getMonth()]
    validYear = date.getUTCFullYear()
    validDay = date.getUTCDate()
    @_mapObjToDOM
      invoiceDate: "#{year} #{month} #{day}"
      expirationDate: "#{validYear} #{validMonth} #{validDay}"
      reminderDate: "#{validDay} #{validMonth} #{validYear} "
    @

  _renderInvoiceTable: ->
    $itemPrototype = $(@$("div#invoice-body table tbody tr.item")[0]).clone()
    @$('div#invoice-body table tbody').empty()
    for index, itemObj of @model.get("invoiceItems")
      $row = $itemPrototype.clone()
      # Calculate the subtotal of this row (cache it in the object)
      itemObj.subtotal = itemObj.price * itemObj.quantity
      # Apply discount over subtotal if it exists
      if itemObj.discount? > 0 then itemObj.subtotal = itemObj.subtotal * (1-itemObj.discount)
      $("td.subtotal", $row).html itemObj.subtotal
      @_mapObjToDOM itemObj, $row
      @$("div#invoice-body table tbody").append $row
    # Table footer part
    footerAggregate = {}
    footerAggregate.subtotal = _.reduce @model.get("invoiceItems"), ((sum, item)-> sum + item.subtotal), 0
    footerAggregate.vat = footerAggregate.subtotal * @model.get("vatPercentage")
    footerAggregate.total = footerAggregate.subtotal + footerAggregate.vat
    @_mapObjToDOM footerAggregate, @$("div#invoice-body table tfoot")
    @