var Backbone = require('backbone');
var _ = require('underscore');
var CustomListView = require('../../../custom-list/custom-view');
var CustomListCollection = require('../../../custom-list/custom-list-collection');
var selectedItemTemplate = require('./select-item.tpl');
var CustomListItemView = require('../../../custom-list/custom-list-item-view');
var itemListTemplate = require('../../../custom-list/custom-list-item.tpl');
var template = require('./select.tpl');
var ENTER_KEY_CODE = 13;

Backbone.Form.editors.Suggest = Backbone.Form.editors.Base.extend({

  tagName: 'div',
  className: 'u-ellipsis Editor-formSelect',

  events: {
    'click .js-button': '_onButtonClick',
    'keydown .js-button': '_onButtonKeyDown',
    'focus .js-button': function () {
      this.trigger('focus', this);
    },
    'blur': function () {
      this.trigger('blur', this);
    }
  },

  options: {
    selectedItemTemplate: selectedItemTemplate,
    itemListTemplate: itemListTemplate,
    customListItemView: CustomListItemView
  },

  initialize: function (opts) {
    Backbone.Form.editors.Base.prototype.initialize.call(this, opts);
    this._setOptions(opts);

    this.template = opts.template || template;

    this._setupCollection();
    this.setValue(this.model.get(this.options.keyAttr));
    this._initBinds();
  },

  render: function () {
    this.setValue(this.value);

    return this;
  },

  _setupCollection: function () {
    this.collection = new CustomListCollection(this.options.options);

    if (this.options.editorAttrs && this.options.editorAttrs.collectionData) {
      var categories = _.map(this.options.editorAttrs.collectionData, function (d) {
        return { label: d, val: d };
      });

      this.collection.reset(categories);
    }
  },

  _initViews: function () {
    var isLoading = this.options.loading;
    var isEmpty = !this.collection.length;
    var isDisabled = !isEmpty ? this.options.disabled : true;
    var name = this.model.get(this.options.keyAttr);
    var isNull = name === null;
    var label = isNull ? 'null' : name;

    this.$el.html(
      this.template({
        label: label,
        keyAttr: this.options.keyAttr,
        isDisabled: isDisabled,
        isLoading: isLoading,
        isEmpty: isEmpty,
        isNull: isNull
      })
    );

    if (isDisabled) {
      this.undelegateEvents();
    }

    this._listView = new CustomListView({
      collection: this.collection,
      showSearch: this.options.showSearch,
      allowFreeTextInput: this.options.allowFreeTextInput,
      typeLabel: this.options.keyAttr,
      itemTemplate: this.options.itemListTemplate,
      itemView: this.options.customListItemView,
      position: this.options.position
    });

    this.$el.append(this._listView.el); // No render from the beginning
  },

  _initBinds: function () {
    this.collection.bind('change:selected', this._onItemSelected, this);
    this.collection.bind('reset', this.render, this);
    this.applyESCBind(function () {
      this._listView.hide();
    });
    this.applyClickOutsideBind(function () {
      this._listView.hide();
    });
  },

  _onItemSelected: function (mdl) {
    this._listView.hide();
    this._renderButton(mdl).focus();
    this.trigger('change', this);
  },

  _onButtonClick: function (ev) {
    this._listView.toggle();
  },

  _onButtonKeyDown: function (ev) {
    if (ev.which === ENTER_KEY_CODE) {
      ev.preventDefault();
      if (!this._listView.isVisible()) {
        ev.stopPropagation();
        this._listView.toggle();
      }
    }
  },

  getValue: function () {
    var item = this.collection.getSelectedItem();

    if (item) {
      return item.getValue();
    }

    return;
  },

  setValue: function (value) {
    var selectedModel = this.collection.setSelected(value);

    if (!selectedModel) {
      this.collection.add({ label: value, val: value });
      selectedModel = this.collection.setSelected(value);
    }

    this._initViews();
    this._renderButton(selectedModel);

    this.value = value;
  },

  _renderButton: function (mdl) {
    var button = this.$('.js-button');
    var name = mdl.getName();
    var isNull = name === null || name === 'null';
    var label = isNull ? 'null' : name;

    var data = _.extend({}, mdl.attributes, { label: label });
    var $html = this.options.selectedItemTemplate(data);

    button
      .html($html)
      .toggleClass('is-empty', isNull);

    return button;
  },

  remove: function () {
    this._listView && this._listView.clean();
    Backbone.Form.editors.Base.prototype.remove.call(this);
  }

});
