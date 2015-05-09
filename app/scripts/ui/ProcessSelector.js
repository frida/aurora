'use strict';

var React = require("react"),
    $ = require("jquery"),
    dd = require("jquery.dd");

const ProcessSelector = React.createClass({
  render() {
    return (
      <div className="process-selector jumbotron">
        <h1>Welcome!</h1>
        <h4>Select a process to get started:</h4>
        <form className="form-horizontal">
          <div className="control-group">
            <label className="control-label">Device</label>
            <div className="controls">
              <select ref="devices">
                <option value="1">Local System</option>
                <option value="2">iPhone</option>
              </select>
            </div>
          </div>
          <div className="control-group">
            <label className="control-label">Process</label>
            <div className="controls">
              <select ref="processes">
                <option value="1234">Facebook</option>
                <option value="5678">Twitter</option>
              </select>
            </div>
          </div>
          <div className="control-group">
            <div className="controls">
              <button className="btn btn-primary large" data-action="attach">Start</button>
            </div>
          </div>
        </form>
      </div>
    );
  },
  componentDidMount() {
      this._updateDropdowns();
  },
  componentDidUpdate(prevProps, prevState) {
      this._updateDropdowns();
  },
  _updateDropdowns() {
      $(React.findDOMNode(this.refs.devices)).msDropDown();
      $(React.findDOMNode(this.refs.processes)).msDropDown();
  }
});

module.exports = ProcessSelector;
